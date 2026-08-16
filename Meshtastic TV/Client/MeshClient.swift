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
import Network
import OSLog
import SwiftData

/// Nonces echoed back by the radio in `config_complete_id`. Mirrors the iOS
/// `AccessoryManager` constants (which we don't link). Sending `wantConfigID`
/// triggers the config dump (NONCE_ONLY_CONFIG) and node-database dump
/// (NONCE_ONLY_DB); older firmware returns the full dump for either nonce.
let NONCE_ONLY_CONFIG: UInt32 = 69420
let NONCE_ONLY_DB: UInt32 = 69421

private enum ConfigWaitState: Equatable {
	case waiting
	case failed
	case completed
}

@MainActor
@Observable
final class MeshClient {

	enum State: Equatable {
		case disconnected
		case connecting
		case reconnecting(attempt: Int, maxAttempts: Int)
		case connected
		case failed(String)
	}

	private(set) var state: State = .disconnected
	private(set) var myNodeNum: UInt32?
	private(set) var host: String = ""
	private(set) var port: Int = 4403

	/// Latest health numbers for the CONNECTED node — the mesh stats strip's data.
	/// In-memory only: session data, and adding fields to `MeshNode` would be a schema
	/// change whose failure path wipes the store (see MeshtasticTVApp.makeContainer).
	struct ConnectedNodeStats: Equatable {
		/// Every field is nil until its telemetry actually arrives, so the strip
		/// renders a dash rather than a fabricated zero. LocalStats fills them all;
		/// the DeviceMetrics fallback and NodeInfo seed fill only the load fields
		/// they carry.
		var channelUtilization: Float?
		var airUtilTx: Float?
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
	/// Owns both the initial connection attempt and any reconnect campaign.
	private var connectTask: Task<Void, Never>?
	private var connectionGeneration = 0
	private var sessionWasConnected = false
	private static let maxReconnectAttempts = 3
	private static let connectionAttemptTimeout: Duration = .seconds(10)
	private var configWaitContinuation: AsyncThrowingStream<Void, Error>.Continuation?
	private var configWaitGeneration: Int?
	private var configWaitState: ConfigWaitState?
#if DEBUG
	private var debugFaultTask: Task<Void, Never>?
	private var didScheduleDebugFault = false
#endif

	// MARK: - Connect / disconnect

	func connect(host: String, port: Int) {
		disconnect()
		self.host = host
		self.port = port
		state = .connecting
		myNodeNum = nil
		// Stats describe one radio's session — they must not survive a switch.
		stats = nil
		// Note: the persisted node store is intentionally NOT cleared here — keeping
		// it is what leaves the map populated across relaunches until the radio's
		// fresh node-DB dump updates it.

		connectionGeneration += 1
		let generation = connectionGeneration
		connectTask = Task {
			do {
				try await self.establishConnectionWithTimeout(host: host, port: port, generation: generation)
			} catch {
				guard self.isCurrent(generation), !Task.isCancelled else { return }
				self.logConnectionFailure(error)
				self.connectionGeneration += 1
				self.teardownConnection()
				self.state = .failed(self.userFacingMessage(for: error))
			}
		}
	}

	func disconnect() {
		connectionGeneration += 1
		sessionWasConnected = false
#if DEBUG
		debugFaultTask?.cancel()
		debugFaultTask = nil
#endif
		connectTask?.cancel()
		connectTask = nil
		teardownConnection()
		state = .disconnected
	}

	private func teardownConnection() {
		consumeTask?.cancel()
		consumeTask = nil
		clearConfigWait()
		let conn = connection
		connection = nil
		Task { try? await conn?.disconnect(withError: nil, shouldReconnect: false) }
	}

	private func establishConnectionWithTimeout(host: String, port: Int, generation: Int) async throws {
		try await withThrowingTaskGroup(of: Void.self) { group in
			group.addTask {
				try await self.establishConnection(host: host, port: port, generation: generation)
			}
			group.addTask {
				try await Task.sleep(for: Self.connectionAttemptTimeout)
				throw AccessoryError.connectionFailed("Connection timed out. Try again.")
			}

			defer { group.cancelAll() }
			try await group.next()
		}
	}

	private func establishConnection(host: String, port: Int, generation: Int) async throws {
		let conn = try await TCPConnection(host: host, port: port)
		guard isCurrent(generation), !Task.isCancelled else {
			try? await conn.disconnect(withError: nil, shouldReconnect: false)
			throw CancellationError()
		}

		connection = conn
		let stream = try await conn.connect()
		guard isCurrent(generation), !Task.isCancelled else {
			try? await conn.disconnect(withError: nil, shouldReconnect: false)
			throw CancellationError()
		}

		// Ask for config, then the node database. The radio streams my_info /
		// node_info / config frames and echoes each nonce in config_complete_id.
		try await conn.send(makeWantConfig(NONCE_ONLY_CONFIG))
		try await conn.send(makeWantConfig(NONCE_ONLY_DB))
		guard isCurrent(generation), !Task.isCancelled else {
			try? await conn.disconnect(withError: nil, shouldReconnect: false)
			throw CancellationError()
		}

		clearConfigWait()
		let configCompletion = AsyncThrowingStream<Void, Error> { continuation in
			configWaitContinuation = continuation
			configWaitGeneration = generation
			configWaitState = .waiting
		}
		consumeTask = Task { [weak self] in
			for await event in stream {
				self?.handle(event, generation: generation)
			}
			guard !Task.isCancelled else { return }
			self?.handleStreamEnd(generation: generation)
		}

		defer { clearConfigWait(generation: generation) }
		var didCompleteConfig = false
		for try await _ in configCompletion {
			didCompleteConfig = true
			break
		}
		guard didCompleteConfig, isCurrent(generation), !Task.isCancelled else {
			throw CancellationError()
		}
	}

	private func beginReconnect(after error: Error?) {
		guard sessionWasConnected else {
			connectionGeneration += 1
			teardownConnection()
			state = .failed(error.map(userFacingMessage(for:)) ?? "Connection closed. Try again.")
			return
		}

		sessionWasConnected = false
		connectionGeneration += 1
		let generation = connectionGeneration
		connectTask?.cancel()
		consumeTask?.cancel()
		consumeTask = nil
		clearConfigWait()
		let oldConnection = connection
		connection = nil

		connectTask = Task {
			try? await oldConnection?.disconnect(withError: nil, shouldReconnect: false)
			var lastError = error
			for attempt in 1...Self.maxReconnectAttempts {
				guard self.isCurrent(generation), !Task.isCancelled else { return }
				self.state = .reconnecting(attempt: attempt, maxAttempts: Self.maxReconnectAttempts)
				do {
					try await self.establishConnectionWithTimeout(host: self.host, port: self.port, generation: generation)
					return
				} catch {
					guard self.isCurrent(generation), !Task.isCancelled else { return }
					lastError = error
					self.logConnectionFailure(error)
					self.consumeTask?.cancel()
					self.consumeTask = nil
					self.clearConfigWait(generation: generation)
					let failedConnection = self.connection
					self.connection = nil
					try? await failedConnection?.disconnect(withError: nil, shouldReconnect: false)
					if attempt < Self.maxReconnectAttempts {
						try? await Task.sleep(for: .seconds(2))
					}
				}
			}

			guard self.isCurrent(generation), !Task.isCancelled else { return }
			self.sessionWasConnected = false
			self.connectionGeneration += 1
			self.teardownConnection()
			self.state = .failed(lastError.map(self.userFacingMessage(for:)) ?? "Connection closed. Try again.")
		}
	}

	private func isCurrent(_ generation: Int) -> Bool {
		generation == connectionGeneration
	}

	private func completeConfigWait(generation: Int) {
		guard configWaitGeneration == generation, configWaitState == .waiting else { return }
		configWaitState = .completed
		configWaitContinuation?.yield(())
		configWaitContinuation?.finish()
	}

	@discardableResult
	private func failConfigWait(_ error: Error, generation: Int) -> Bool {
		guard configWaitGeneration == generation else { return false }
		switch configWaitState {
		case .waiting:
			configWaitState = .failed
			configWaitContinuation?.finish(throwing: error)
			return true
		case .failed:
			return true
		case .completed, .none:
			return false
		}
	}

	private func clearConfigWait(generation: Int? = nil) {
		if let generation, configWaitGeneration != generation { return }
		configWaitContinuation?.finish()
		configWaitContinuation = nil
		configWaitGeneration = nil
		configWaitState = nil
	}

	private func logConnectionFailure(_ error: Error) {
		Logger.transport.error("📺 [MeshClient] connection failed: \(error.localizedDescription, privacy: .public)")
	}

	private func userFacingMessage(for error: Error) -> String {
		let nsError = error as NSError
		if error is NWError || nsError.domain == "Network.NWError" {
			return "Couldn't connect. Check your network and try again."
		}
		return error.localizedDescription
	}

#if DEBUG
	/// Deterministic simulator fault injection for the tvOS reconnect UI.
	private func scheduleDebugConnectionAbortIfRequested() {
		guard !didScheduleDebugFault,
		      let index = CommandLine.arguments.firstIndex(of: "-tv-simulate-abort-after"),
		      index + 1 < CommandLine.arguments.count,
		      let delay = Double(CommandLine.arguments[index + 1]), delay >= 0 else { return }
		didScheduleDebugFault = true
		debugFaultTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(delay))
			guard !Task.isCancelled, let self, self.sessionWasConnected else { return }
			if let portIndex = CommandLine.arguments.firstIndex(of: "-tv-reconnect-port"),
			   portIndex + 1 < CommandLine.arguments.count,
			   let reconnectPort = Int(CommandLine.arguments[portIndex + 1]),
			   (1...65535).contains(reconnectPort) {
				self.port = reconnectPort
			}
			self.beginReconnect(after: NWError.posix(.ECONNABORTED))
		}
	}
#endif

	private func makeWantConfig(_ nonce: UInt32) -> ToRadio {
		var toRadio = ToRadio()
		toRadio.wantConfigID = nonce
		return toRadio
	}

	// MARK: - Event handling

	private func handleStreamEnd(generation: Int) {
		guard isCurrent(generation) else { return }
		let error = AccessoryError.connectionFailed("Connection closed. Try again.")
		if failConfigWait(error, generation: generation) { return }
		beginReconnect(after: nil)
	}

	private func handle(_ event: ConnectionEvent, generation: Int) {
		guard isCurrent(generation) else { return }

		switch event {
		case .data(let fromRadio):
			ingest(fromRadio, generation: generation)
		case .disconnected(let shouldReconnect):
			if shouldReconnect {
				let error = AccessoryError.connectionFailed("Connection closed. Try again.")
				if failConfigWait(error, generation: generation) { return }
				beginReconnect(after: nil)
			} else {
				connectionGeneration += 1
				sessionWasConnected = false
				teardownConnection()
				state = .disconnected
			}
		case .error(let error):
			if failConfigWait(error, generation: generation) { return }
			beginReconnect(after: error)
		case .errorWithoutReconnect(let error):
			connectionGeneration += 1
			sessionWasConnected = false
			teardownConnection()
			logConnectionFailure(error)
			state = .failed(userFacingMessage(for: error))
		case .logMessage, .rssiUpdate:
			break
		}
	}

	/// Slim analogue of the iOS `processFromRadio` — only the frames a live map needs.
	private func ingest(_ fromRadio: FromRadio, generation: Int) {
		switch fromRadio.payloadVariant {
		case .myInfo(let myInfo):
			myNodeNum = myInfo.myNodeNum

		case .nodeInfo(let info):
			upsertNodeInfo(info)

		case .packet(let packet):
			ingestPacket(packet)

		case .configCompleteID:
			// Initial dump finished — we have the node database; go live.
			sessionWasConnected = true
			if state != .connected { state = .connected }
			completeConfigWait(generation: generation)
#if DEBUG
			scheduleDebugConnectionAbortIfRequested()
#endif

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
		var updated = stats ?? ConnectedNodeStats(receivedAt: Date())
		if metrics.hasChannelUtilization { updated.channelUtilization = metrics.channelUtilization }
		if metrics.hasAirUtilTx { updated.airUtilTx = metrics.airUtilTx }
		updated.receivedAt = Date()
		stats = updated
	}
}
