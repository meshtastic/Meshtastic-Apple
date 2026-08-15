//
//  MeshClient.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Thin, in-memory TCP client for a Meshtastic node. Reuses the portable
//  `TCPConnection` actor (Network.framework) and reimplements only the minimal
//  want-config / want-database handshake — none of the iOS `AccessoryManager`
//  state machine, SwiftData persistence, BLE, CoreLocation, MQTT or TAK.
//

import Foundation
import MeshtasticProtobufs
import OSLog
import SwiftData

/// Nonces echoed back by the radio in `config_complete_id`. Mirrors the iOS
/// `AccessoryManager` constants (which we don't link). Sending `wantConfigID`
/// triggers the config dump (NONCE_ONLY_CONFIG) and node-database dump
/// (NONCE_ONLY_DB); older firmware returns the full dump for either nonce.
let NONCE_ONLY_CONFIG: UInt32 = 69420
let NONCE_ONLY_DB: UInt32 = 69421

@MainActor
@Observable
final class MeshClient {

	enum State: Equatable {
		case disconnected
		case connecting
		case connected
		case failed(String)
	}

	private(set) var state: State = .disconnected
	private(set) var myNodeNum: UInt32?
	private(set) var host: String = ""

	/// Latest health numbers for the CONNECTED node — the mesh stats strip's data.
	/// In-memory only: session data, and adding fields to `MeshNode` would be a schema
	/// change whose failure path wipes the store (see MeshtasticTVApp.makeContainer).
	struct ConnectedNodeStats: Equatable {
		var channelUtilization: Float
		var airUtilTx: Float
		/// Nil until the first LocalStats packet arrives — the DeviceMetrics
		/// fallback and the NodeInfo seed only carry the two load fields above.
		var packetsTx: UInt32?
		var packetsRx: UInt32?
		var packetsRxDupe: UInt32?
		var onlineNodes: UInt32?
		var totalNodes: UInt32?
		var receivedAt: Date
	}
	private(set) var stats: ConnectedNodeStats?

	/// The tvOS-local SwiftData store the map and list read via `@Query`. Every
	/// upsert lands here; nothing is kept in memory, so the map survives relaunch.
	private let context: ModelContext

	init(context: ModelContext) {
		self.context = context
	}

	private var connection: TCPConnection?
	private var consumeTask: Task<Void, Never>?
	/// The in-flight connect attempt. Tracked so `disconnect()` (and a fresh `connect()`) can cancel
	/// an attempt still awaiting the TCP handshake — otherwise a stale attempt could resume later and
	/// clobber the connection/consumeTask a newer attempt already set up, orphaning its TCPConnection.
	private var connectTask: Task<Void, Never>?

	// MARK: - Connect / disconnect

	func connect(host: String, port: Int) {
		disconnect()
		self.host = host
		state = .connecting
		myNodeNum = nil
		// Stats describe one radio's session — they must not survive a switch.
		stats = nil
		// Note: the persisted node store is intentionally NOT cleared here — keeping
		// it is what leaves the map populated across relaunches until the radio's
		// fresh node-DB dump updates it.

		connectTask = Task {
			do {
				let conn = try await TCPConnection(host: host, port: port)
				// A newer connect()/disconnect() may have cancelled this attempt while it awaited the
				// handshake. If so, tear down this now-orphaned connection rather than clobbering the
				// state the newer attempt already set up.
				guard !Task.isCancelled else {
					try? await conn.disconnect(withError: nil, shouldReconnect: false)
					return
				}
				self.connection = conn
				let stream = try await conn.connect()

				// Ask for config, then the node database. The radio streams
				// my_info / node_info / config frames and echoes each nonce back
				// in a config_complete_id when that dump finishes.
				try await conn.send(makeWantConfig(NONCE_ONLY_CONFIG))
				try await conn.send(makeWantConfig(NONCE_ONLY_DB))

				consumeTask = Task { [weak self] in
					for await event in stream {
						await self?.handle(event)
					}
				}
			} catch {
				// A superseded attempt — cancelled by a newer connect()/disconnect() while awaiting
				// conn.connect() or the wantConfig sends — must not clobber the newer attempt's state
				// to .failed. Unwind quietly; the newer attempt owns `state` now.
				guard !Task.isCancelled else { return }
				Logger.transport.error("📺 [MeshClient] connect failed: \(error.localizedDescription, privacy: .public)")
				self.state = .failed(error.localizedDescription)
			}
		}
	}

	func disconnect() {
		connectTask?.cancel()
		connectTask = nil
		consumeTask?.cancel()
		consumeTask = nil
		let conn = connection
		connection = nil
		Task { try? await conn?.disconnect(withError: nil, shouldReconnect: false) }
		state = .disconnected
	}

	private func makeWantConfig(_ nonce: UInt32) -> ToRadio {
		var toRadio = ToRadio()
		toRadio.wantConfigID = nonce
		return toRadio
	}

	// MARK: - Event handling

	private func handle(_ event: ConnectionEvent) {
		switch event {
		case .data(let fromRadio):
			ingest(fromRadio)
		case .disconnected:
			state = .disconnected
		case .error(let error), .errorWithoutReconnect(let error):
			state = .failed(error.localizedDescription)
		case .logMessage, .rssiUpdate:
			break
		}
	}

	/// Slim analogue of the iOS `processFromRadio` — only the frames a live map needs.
	private func ingest(_ fromRadio: FromRadio) {
		switch fromRadio.payloadVariant {
		case .myInfo(let myInfo):
			myNodeNum = myInfo.myNodeNum

		case .nodeInfo(let info):
			upsertNodeInfo(info)

		case .packet(let packet):
			ingestPacket(packet)

		case .configCompleteID:
			// Initial dump finished — we have the node database; go live.
			if state != .connected { state = .connected }

		default:
			break
		}
	}

	/// Fetch the persisted node for `num`, or insert a fresh one. The main context's
	/// fetch reflects pending inserts, so back-to-back frames for a brand-new node
	/// reuse the same row rather than duplicating it (all ingest is serial on the
	/// main actor, so there is no insert race).
	private func node(for num: UInt32) -> MeshNode {
		let raw = Int(num)
		var descriptor = FetchDescriptor<MeshNode>(predicate: #Predicate { $0.numRaw == raw })
		descriptor.fetchLimit = 1
		if let existing = try? context.fetch(descriptor).first { return existing }
		let node = MeshNode(num: num)
		context.insert(node)
		return node
	}

	private func upsertNodeInfo(_ info: NodeInfo) {
		let node = node(for: info.num)

		// Guard every assignment: writing an unchanged value still marks the model
		// dirty and re-runs the map/list @Query, and a busy mesh re-sends NodeInfo
		// frequently with nothing new in it.
		if info.hasUser {
			// Only overwrite the generated "Meshtastic <last4>" default with a real,
			// non-empty name — some nodes broadcast NodeInfo with empty user fields, and
			// clobbering the default with "" would put the "?" back.
			if !info.user.longName.isEmpty, node.longName != info.user.longName {
				node.longName = info.user.longName
			}
			if !info.user.shortName.isEmpty, node.shortName != info.user.shortName {
				node.shortName = info.user.shortName
			}
			let role = Int(info.user.role.rawValue)
			if node.roleValue != role { node.roleValue = role }
			let hw = String(describing: info.user.hwModel)
			if node.hwModel != hw { node.hwModel = hw }
		}
		if info.hasPosition, info.position.hasLatitudeI, info.position.hasLongitudeI {
			let lat = Double(info.position.latitudeI) * 1e-7
			let lon = Double(info.position.longitudeI) * 1e-7
			if node.latitude != lat { node.latitude = lat }
			if node.longitude != lon { node.longitude = lon }
		}
		if info.hasDeviceMetrics {
			let battery = Int(info.deviceMetrics.batteryLevel)
			if node.batteryLevel != battery { node.batteryLevel = battery }
			// The config dump includes the connected node's own entry; seeding here puts
			// numbers in the stats strip at connect time instead of waiting out the first
			// telemetry broadcast interval.
			if info.num == myNodeNum {
				applyDeviceMetrics(info.deviceMetrics)
			}
		}
		if info.lastHeard > 0 {
			let heard = Date(timeIntervalSince1970: TimeInterval(info.lastHeard))
			if node.lastHeard != heard { node.lastHeard = heard }
		}
		if info.snr != 0, node.snr != info.snr { node.snr = info.snr }
	}

	private func ingestPacket(_ packet: MeshPacket) {
		guard case .decoded(let data) = packet.payloadVariant else { return }
		switch data.portnum {
		case .positionApp:
			ingestPosition(packet, data)
		case .telemetryApp:
			ingestTelemetry(packet, data)
		default:
			break
		}
	}

	private func ingestPosition(_ packet: MeshPacket, _ data: DataMessage) {
		guard let position = try? Position(serializedBytes: data.payload),
		      position.hasLatitudeI, position.hasLongitudeI else { return }

		let latitude = Double(position.latitudeI) * 1e-7
		let longitude = Double(position.longitudeI) * 1e-7
		let node = node(for: packet.from)
		// Only write when the fix moved, or lastHeard is meaningfully stale —
		// stationary nodes beacon their position constantly, and bumping lastHeard
		// on every packet would re-run the map @Query each time for no visible change.
		let moved = node.latitude != latitude || node.longitude != longitude
		let stale = (node.lastHeard.map { Date().timeIntervalSince($0) > 60 }) ?? true
		guard moved || stale else { return }
		node.latitude = latitude
		node.longitude = longitude
		node.lastHeard = Date()
	}

	/// Telemetry from the CONNECTED node feeds the stats strip. Other nodes' telemetry is
	/// dropped: their LocalStats describe *their* node DB and radio load, not this mesh
	/// session's, and this client keeps no per-node telemetry history.
	private func ingestTelemetry(_ packet: MeshPacket, _ data: DataMessage) {
		guard let myNodeNum, packet.from == myNodeNum,
		      let telemetry = try? Telemetry(serializedBytes: data.payload) else { return }
		switch telemetry.variant {
		case .localStats(let localStats):
			// No no-op guard, unlike the store writes above: `receivedAt` drives the
			// strip's age text, so every arrival is a real update by definition.
			stats = ConnectedNodeStats(
				channelUtilization: localStats.channelUtilization,
				airUtilTx: localStats.airUtilTx,
				packetsTx: localStats.numPacketsTx,
				packetsRx: localStats.numPacketsRx,
				packetsRxDupe: localStats.numRxDupe,
				onlineNodes: localStats.numOnlineNodes,
				totalNodes: localStats.numTotalNodes,
				receivedAt: Date()
			)
			Logger.transport.info("📺 [MeshClient] LocalStats: ch \(localStats.channelUtilization, privacy: .public)% air \(localStats.airUtilTx, privacy: .public)% tx \(localStats.numPacketsTx, privacy: .public) rx \(localStats.numPacketsRx, privacy: .public) nodes \(localStats.numOnlineNodes, privacy: .public)/\(localStats.numTotalNodes, privacy: .public)")
		case .deviceMetrics(let deviceMetrics):
			applyDeviceMetrics(deviceMetrics)
		default:
			break
		}
	}

	/// Partial stats update from DeviceMetrics — the load fields only, keeping any
	/// LocalStats counters already held. Also the seed path from the connected node's
	/// NodeInfo, so the strip has numbers at connect time.
	private func applyDeviceMetrics(_ metrics: DeviceMetrics) {
		guard metrics.hasChannelUtilization || metrics.hasAirUtilTx else { return }
		var updated = stats ?? ConnectedNodeStats(channelUtilization: 0, airUtilTx: 0, receivedAt: Date())
		if metrics.hasChannelUtilization { updated.channelUtilization = metrics.channelUtilization }
		if metrics.hasAirUtilTx { updated.airUtilTx = metrics.airUtilTx }
		updated.receivedAt = Date()
		stats = updated
	}
}
