//
//  AccessoryManager+AdditionalRadios.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs
import OSLog

// MARK: - Additional radios (feature 021, Phase 5)

/// A radio connected alongside the focused one.
///
/// The focused radio (`AccessoryManager.activeConnection`) keeps the full connect flow: config
/// refresh, MQTT, location, TAK, firmware gate, settings. An additional radio runs a smaller
/// flow on its own connection: connect, config and node-DB handshake, then ingest into the
/// shared store, tagged with its own node number. Nothing it does touches the focused radio's
/// state (see `processAdditionalFromRadio`).
@MainActor
final class AdditionalRadio: Identifiable {
	let session: RadioSession
	var eventTask: Task<Void, Never>?
	var heartbeatTask: Task<Void, Never>?
	/// Handshake requests waiting for their `configCompleteID`, by nonce.
	var pendingNonces: [UInt32: CheckedContinuation<Void, Error>] = [:]
	/// Nodes received in the current node-DB dump.
	var nodeCount = 0

	var id: UUID { session.device.id }

	init(session: RadioSession) {
		self.session = session
	}
}

/// What to do when the user connects a radio while another one is connected (D-05).
enum AdditionalRadioBehavior: String, Codable, CaseIterable, Identifiable {
	case ask
	case keepBoth
	case switchRadio

	var id: String { rawValue }

	var label: String {
		switch self {
		case .ask: return "Ask Each Time".localized
		case .keepBoth: return "Keep Both Connected".localized
		case .switchRadio: return "Switch Radios".localized
		}
	}
}

extension AccessoryManager {

	/// At most this many radios at once, the focused one included (D-10).
	static let maxConnectedRadios = 4

	/// Radios connected now: the focused one plus the additional ones.
	var connectedRadioCount: Int {
		(activeConnection == nil ? 0 : 1) + additionalRadios.count
	}

	var canConnectAnotherRadio: Bool {
		connectedRadioCount < Self.maxConnectedRadios
	}

	/// True when `deviceId` is connected or connecting, focused or not.
	func isRadioConnected(_ deviceId: UUID) -> Bool {
		activeConnection?.device.id == deviceId || additionalRadios[deviceId] != nil
	}

	/// Every connected radio's device, the focused one first.
	var connectedRadios: [Device] {
		var result: [Device] = []
		if let focused = activeConnection?.device { result.append(focused) }
		return result + additionalRadioDevices
	}

	/// The additional radios' devices, by name.
	var additionalRadioDevices: [Device] {
		additionalRadios.values
			.map(\.session.device)
			.sorted { ($0.longName ?? $0.name) < ($1.longName ?? $1.name) }
	}

	func additionalRadio(for session: RadioSession) -> AdditionalRadio? {
		additionalRadios[session.device.id].flatMap { $0.session === session ? $0 : nil }
	}

	// MARK: - Connect

	/// Connects `device` alongside the focused radio. With no radio connected this is a normal
	/// connect, and the radio becomes the focused one.
	func connectAdditionalRadio(_ device: Device) async throws {
		guard activeConnection != nil else {
			try await connect(to: device)
			return
		}
		guard !isRadioConnected(device.id) else {
			throw AccessoryError.connectionFailed("This radio is already connected")
		}
		guard canConnectAnotherRadio else {
			throw AccessoryError.connectionFailed(String.localizedStringWithFormat("You can connect up to %d radios at once.".localized, Self.maxConnectedRadios))
		}
		guard let transport = transportForType(device.transportType) else {
			throw AccessoryError.connectionFailed("No transport for type")
		}
		Logger.transport.info("🔗➕ [Additional] Connecting \(device.name, privacy: .public) alongside \(self.activeConnection?.device.name ?? "?", privacy: .public)")
		updateDevice(deviceId: device.id, key: \.connectionState, value: .connecting)

		let connection: any Connection
		let events: AsyncStream<ConnectionEvent>
		do {
			connection = try await transport.connect(to: device)
			events = try await connection.connect()
		} catch {
			updateDevice(deviceId: device.id, key: \.connectionState, value: .disconnected)
			if let bleTransport = transport as? BLETransport {
				await bleTransport.resumeScanningAfterConnectionEstablished()
			}
			throw error
		}

		let session = RadioSession(device: device, connection: connection)
		let radio = AdditionalRadio(session: session)
		additionalRadios[device.id] = radio
		radio.eventTask = Task { @MainActor [weak self] in
			for await event in events {
				await self?.didReceive(event, from: session)
			}
			Logger.transport.info("🔗➕ [Additional] Event stream closed for \(device.name, privacy: .public)")
		}

		do {
			try await sendAdditionalHeartbeat(radio)
			try await requestHandshake(radio, nonce: UInt32(NONCE_ONLY_CONFIG), timeout: .seconds(30))
			try await requestHandshake(radio, nonce: UInt32(NONCE_ONLY_DB), timeout: .seconds(120))
		} catch {
			Logger.transport.error("🔗➕ [Additional] Handshake with \(device.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
			await disconnectAdditionalRadio(device.id)
			throw error
		}

		await MeshPackets.shared.flushDebouncedSaves()
		updateDevice(deviceId: device.id, key: \.connectionState, value: .connected)
		if transport.requiresPeriodicHeartbeat {
			startAdditionalHeartbeat(radio)
		}
		if let bleTransport = transport as? BLETransport {
			await bleTransport.resumeScanningAfterConnectionEstablished()
		}
		WatchSessionManager.shared.sendNodesToWatch()
		Logger.transport.info("🔗➕ [Additional] \(session.device.longName ?? device.name, privacy: .public) connected (\(radio.nodeCount) nodes); \(self.connectedRadioCount) radios connected")
	}

	/// Sends a want-config request and waits for its completion nonce.
	private func requestHandshake(_ radio: AdditionalRadio, nonce: UInt32, timeout: Duration) async throws {
		if nonce == UInt32(NONCE_ONLY_DB) {
			radio.nodeCount = 0
		}
		let connection = radio.session.connection
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			radio.pendingNonces[nonce] = continuation
			Task { @MainActor [weak self] in
				do {
					var toRadio = ToRadio()
					toRadio.wantConfigID = nonce
					try await connection.send(toRadio)
					try await connection.startDrainPendingPackets()
				} catch {
					self?.finishHandshake(radio, nonce: nonce, error: error)
				}
			}
			Task { @MainActor [weak self] in
				try? await Task.sleep(for: timeout)
				self?.finishHandshake(radio, nonce: nonce, error: AccessoryError.timeout)
			}
		}
	}

	private func finishHandshake(_ radio: AdditionalRadio, nonce: UInt32, error: Error?) {
		guard let continuation = radio.pendingNonces.removeValue(forKey: nonce) else { return }
		if let error {
			continuation.resume(throwing: error)
		} else {
			continuation.resume()
		}
	}

	/// A heartbeat on this radio's own connection. Unlike `sendHeartbeat`, it leaves the focused
	/// radio's heartbeat timers alone.
	private func sendAdditionalHeartbeat(_ radio: AdditionalRadio) async throws {
		var heartbeat = Heartbeat()
		heartbeat.nonce = UInt32.random(in: 2...UInt32.max)
		var toRadio = ToRadio()
		toRadio.payloadVariant = .heartbeat(heartbeat)
		try await radio.session.connection.send(toRadio)
	}

	private func startAdditionalHeartbeat(_ radio: AdditionalRadio) {
		radio.heartbeatTask?.cancel()
		radio.heartbeatTask = Task { @MainActor [weak self, weak radio] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
				guard let self, let radio, !Task.isCancelled else { return }
				do {
					try await self.sendAdditionalHeartbeat(radio)
				} catch {
					Logger.transport.error("🔗➕ [Additional] Heartbeat to \(radio.session.device.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
					await self.disconnectAdditionalRadio(radio.id)
					return
				}
			}
		}
	}

	// MARK: - Disconnect

	/// Disconnects one additional radio. The focused radio and the others are unaffected.
	func disconnectAdditionalRadio(_ deviceId: UUID) async {
		guard let radio = additionalRadios.removeValue(forKey: deviceId) else { return }
		retiredAdditionalSessionIDs.insert(radio.session.id)
		radio.heartbeatTask?.cancel()
		let pending = radio.pendingNonces
		radio.pendingNonces.removeAll()
		for continuation in pending.values {
			continuation.resume(throwing: AccessoryError.disconnected("Radio disconnected"))
		}
		await MeshPackets.shared.flushDebouncedSaves()
		try? await radio.session.connection.disconnect(withError: nil, shouldReconnect: false)
		radio.eventTask?.cancel()
		updateDevice(deviceId: deviceId, key: \.connectionState, value: .disconnected)
		Logger.transport.info("🔗➖ [Additional] Disconnected \(radio.session.device.name, privacy: .public); \(self.connectedRadioCount) radios connected")
	}

	func disconnectAllAdditionalRadios() async {
		for deviceId in Array(additionalRadios.keys) {
			await disconnectAdditionalRadio(deviceId)
		}
	}

	// MARK: - Events

	/// Handles one event from an additional radio.
	func didReceiveAdditional(_ event: ConnectionEvent, radio: AdditionalRadio) async {
		switch event {
		case .data(let fromRadio):
			await processAdditionalFromRadio(fromRadio, radio: radio)
		case .logMessage(let message):
			didReceiveLog(message: message)
		case .rssiUpdate(let rssi):
			updateDevice(deviceId: radio.id, key: \.rssi, value: rssi)
		case .error(let error), .errorWithoutReconnect(let error):
			Logger.transport.error("🔗➕ [Additional] \(radio.session.device.name, privacy: .public) reported: \(error.localizedDescription, privacy: .public)")
			await disconnectAdditionalRadio(radio.id)
		case .disconnected:
			await disconnectAdditionalRadio(radio.id)
		}
	}

	/// Routes one `FromRadio` from an additional radio. Mesh packets take the same path as the
	/// focused radio's (`processFromRadio`), which is already scoped to the session. The
	/// handshake variants are handled here without the focused-radio side effects: no
	/// preferred-radio update, no foreign-store reset, no connect-flow state, no MQTT, no
	/// follow-up admin requests.
	private func processAdditionalFromRadio(_ fromRadio: FromRadio, radio: AdditionalRadio) async {
		let session = radio.session
		switch fromRadio.payloadVariant {
		case .packet:
			await processFromRadio(fromRadio, session: session)

		case .myInfo(let myInfo):
			let nodeNum = Int64(myInfo.myNodeNum)
			if let focusedNum = activeConnection?.device.num, focusedNum == nodeNum {
				Logger.transport.error("🔗➕ [Additional] \(session.device.name, privacy: .public) reports the focused radio's node number; disconnecting it")
				await disconnectAdditionalRadio(radio.id)
				return
			}
			updateDevice(deviceId: session.device.id, key: \.num, value: nodeNum)
			_ = await MeshPackets.shared.myInfoPacket(myInfo: myInfo, peripheralId: session.device.id.uuidString)
			if session.device.longName == nil {
				updateDevice(deviceId: session.device.id, key: \.longName, value: session.device.name)
			}

		case .nodeInfo(let nodeInfo):
			guard nodeInfo.num > 0 else { return }
			radio.nodeCount += 1
			_ = await MeshPackets.shared.nodeInfoPacket(nodeInfo: nodeInfo, channel: 0, deferSave: true, connectedNodeNum: session.nodeNum)
			if session.nodeNum == Int64(nodeInfo.num), nodeInfo.hasUser {
				let user = nodeInfo.user
				updateDevice(deviceId: session.device.id, key: \.shortName, value: user.shortName.isEmpty ? "?" : user.shortName)
				updateDevice(deviceId: session.device.id, key: \.longName, value: user.longName.isEmpty ? "Unknown".localized : user.longName)
				updateDevice(deviceId: session.device.id, key: \.hardwareModel, value: String(describing: user.hwModel).uppercased())
			}

		case .channel(let channel):
			await handleChannel(channel, session: session)

		case .config(let config):
			guard let nodeNum = session.nodeNum else { return }
			await MeshPackets.shared.localConfig(config: config, nodeNum: nodeNum, nodeLongName: session.device.longName ?? session.device.name)

		case .moduleConfig(let moduleConfig):
			guard let nodeNum = session.nodeNum else { return }
			await MeshPackets.shared.moduleConfig(config: moduleConfig, nodeNum: nodeNum, nodeLongName: session.device.longName ?? session.device.name)

		case .metadata(let metadata):
			guard let nodeNum = session.nodeNum else { return }
			updateDevice(deviceId: session.device.id, key: \.firmwareVersion, value: metadata.firmwareVersion)
			await MeshPackets.shared.deviceMetadataPacket(metadata: metadata, fromNum: nodeNum)

		case .configCompleteID(let nonce):
			if nonce == UInt32(NONCE_ONLY_DB) {
				await MeshPackets.shared.flushDebouncedSaves()
			}
			finishHandshake(radio, nonce: nonce, error: nil)

		case .logRecord(let record):
			didReceiveLog(message: record.stringRepresentation)

		case .rebooted:
			Logger.transport.info("🔗➕ [Additional] \(session.device.name, privacy: .public) rebooted; refreshing its config")
			Task { @MainActor [weak self] in
				guard let self, self.additionalRadios[radio.id] === radio else { return }
				try? await self.requestHandshake(radio, nonce: UInt32(NONCE_ONLY_CONFIG), timeout: .seconds(30))
			}

		default:
			Logger.transport.debug("🔗➕ [Additional] Unhandled FromRadio variant from \(session.device.name, privacy: .public)")
		}
	}
}
