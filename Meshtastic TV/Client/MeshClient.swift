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
	private(set) var nodes: [UInt32: MeshNode] = [:]
	private(set) var myNodeNum: UInt32?
	private(set) var host: String = ""

	private var connection: TCPConnection?
	private var consumeTask: Task<Void, Never>?

	/// Nodes that have a usable position, most-recently-heard first — the map's data source.
	var locatedNodes: [MeshNode] {
		nodes.values
			.filter { $0.hasLocation }
			.sorted { ($0.lastHeard ?? .distantPast) > ($1.lastHeard ?? .distantPast) }
	}

	/// All nodes for the side list, located ones first then by name.
	var sortedNodes: [MeshNode] {
		nodes.values.sorted {
			if $0.hasLocation != $1.hasLocation { return $0.hasLocation }
			return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
		}
	}

	// MARK: - Connect / disconnect

	func connect(host: String, port: Int) {
		disconnect()
		self.host = host
		state = .connecting
		nodes = [:]
		myNodeNum = nil

		Task {
			do {
				let conn = try await TCPConnection(host: host, port: port)
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
				Logger.transport.error("📺 [MeshClient] connect failed: \(error.localizedDescription, privacy: .public)")
				self.state = .failed(error.localizedDescription)
			}
		}
	}

	func disconnect() {
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

	private func upsertNodeInfo(_ info: NodeInfo) {
		var node = nodes[info.num] ?? MeshNode(num: info.num)

		if info.hasUser {
			node.longName = info.user.longName
			node.shortName = info.user.shortName
			node.role = String(describing: info.user.role)
			node.hwModel = String(describing: info.user.hwModel)
		}
		if info.hasPosition, info.position.hasLatitudeI, info.position.hasLongitudeI {
			node.latitude = Double(info.position.latitudeI) * 1e-7
			node.longitude = Double(info.position.longitudeI) * 1e-7
		}
		if info.hasDeviceMetrics {
			node.batteryLevel = Int(info.deviceMetrics.batteryLevel)
		}
		if info.lastHeard > 0 {
			node.lastHeard = Date(timeIntervalSince1970: TimeInterval(info.lastHeard))
		}
		if info.snr != 0 {
			node.snr = info.snr
		}

		// Every write republishes and re-runs the map/list diff, so skip no-ops —
		// a busy mesh re-sends NodeInfo frequently with nothing new in it.
		if nodes[info.num] != node {
			nodes[info.num] = node
		}
	}

	private func ingestPacket(_ packet: MeshPacket) {
		guard case .decoded(let data) = packet.payloadVariant else { return }
		guard data.portnum == .positionApp,
		      let position = try? Position(serializedBytes: data.payload),
		      position.hasLatitudeI, position.hasLongitudeI else { return }

		var node = nodes[packet.from] ?? MeshNode(num: packet.from)
		let latitude = Double(position.latitudeI) * 1e-7
		let longitude = Double(position.longitudeI) * 1e-7
		// Only publish when the fix moved, or lastHeard is meaningfully stale —
		// stationary nodes beacon their position constantly, and bumping lastHeard
		// on every packet would re-diff the map each time for no visible change.
		let moved = node.latitude != latitude || node.longitude != longitude
		let stale = (node.lastHeard.map { Date().timeIntervalSince($0) > 60 }) ?? true
		guard moved || stale else { return }
		node.latitude = latitude
		node.longitude = longitude
		node.lastHeard = Date()
		nodes[packet.from] = node
	}
}
