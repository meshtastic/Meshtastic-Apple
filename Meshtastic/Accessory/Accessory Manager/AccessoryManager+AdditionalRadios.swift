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
	/// A lock-down passphrase saved for this radio has been sent on this connection (T065).
	var lockdownAutoAttempted = false

	var id: UUID { session.device.id }

	init(session: RadioSession) {
		self.session = session
	}
}

/// Lets one radio at a time run its config and node-DB handshake (T064).
///
/// Two dumps at once double the ingest load, and the focused radio's connect recycles the
/// ingest actor at its end (`MeshPackets.recreateShared()`), which must not happen in the
/// middle of another radio's dump. Waiters are served in order.
@MainActor
final class HandshakeGate {
	private(set) var isBusy = false
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func acquire() async {
		guard isBusy else {
			isBusy = true
			return
		}
		await withCheckedContinuation { waiters.append($0) }
	}

	func release() {
		if waiters.isEmpty {
			isBusy = false
		} else {
			waiters.removeFirst().resume()
		}
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
	/// connect, and the radio becomes the focused one. `connectTimeout` bounds the transport
	/// connect for automatic attempts; a user's tap waits as long as the transport does.
	func connectAdditionalRadio(_ device: Device, connectTimeout: Duration? = nil) async throws {
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
			connection = try await connectTransport(transport, to: device, within: connectTimeout)
			// The connect can take a while (BLE waits for the radio). Re-check what it assumed.
			guard !isRadioConnected(device.id), canConnectAnotherRadio, activeConnection != nil else {
				try? await connection.disconnect(withError: nil, shouldReconnect: false)
				throw AccessoryError.connectionFailed("No longer room for this radio")
			}
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
			if handshakeGate.isBusy {
				Logger.transport.info("🔗➕ [Additional] \(device.name, privacy: .public) waits for another radio's handshake")
			}
			await handshakeGate.acquire()
			defer { handshakeGate.release() }
			guard additionalRadios[device.id] === radio else {
				throw AccessoryError.disconnected("Radio disconnected while waiting to connect")
			}
			try await sendAdditionalHeartbeat(radio)
			try await requestHandshake(radio, nonce: UInt32(NONCE_ONLY_CONFIG), timeout: .seconds(30))
			try checkAdditionalRadioFirmware(radio)
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
		if let nodeNum = session.nodeNum {
			await MeshPackets.shared.noteRadioConnected(nodeNum: nodeNum, transport: device.transportType, autoConnect: true)
		}
		if session.device.isManualConnection {
			ManualConnectionList.shared.insert(device: session.device)
		}
		Logger.transport.info("🔗➕ [Additional] \(session.device.longName ?? device.name, privacy: .public) connected (\(radio.nodeCount) nodes); \(self.connectedRadioCount) radios connected")
	}

	/// `transport.connect(to:)`, given up after `timeout` when there is one. A BLE connect to an
	/// out-of-range radio otherwise waits indefinitely, holding the scan paused.
	private func connectTransport(_ transport: any Transport, to device: Device, within timeout: Duration?) async throws -> any Connection {
		guard let timeout else {
			return try await transport.connect(to: device)
		}
		let connection = try await withThrowingTaskGroup(of: (any Connection)?.self) { group -> (any Connection)? in
			group.addTask { try await transport.connect(to: device) }
			group.addTask {
				try? await Task.sleep(for: timeout)
				return nil
			}
			let first = try await group.next() ?? nil
			group.cancelAll()
			if first == nil {
				// Timed out. The connect may still finish as it is cancelled; close anything it made.
				while let late = try? await group.next() {
					if let late {
						try? await late.disconnect(withError: nil, shouldReconnect: false)
					}
				}
			}
			return first
		}
		guard let connection else {
			if let bleTransport = transport as? BLETransport {
				await bleTransport.abandonPendingConnect(to: device.id)
			}
			throw AccessoryError.timeout
		}
		return connection
	}

	/// Sends a want-config request and waits for its completion nonce.
	func requestHandshake(_ radio: AdditionalRadio, nonce: UInt32, timeout: Duration) async throws {
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

	func finishHandshake(_ radio: AdditionalRadio, nonce: UInt32, error: Error?) {
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
					self.scheduleAdditionalRadioReconnect(radio.session.device)
					return
				}
			}
		}
	}

	// MARK: - Disconnect

	/// Disconnects one additional radio. The focused radio and the others are unaffected.
	/// `byUser` also stops any automatic reconnect for it, now and at the next launch.
	func disconnectAdditionalRadio(_ deviceId: UUID, byUser: Bool = false) async {
		if byUser {
			additionalRadioReconnects.removeValue(forKey: deviceId)?.cancel()
		}
		guard let radio = additionalRadios.removeValue(forKey: deviceId) else { return }
		if byUser, let nodeNum = radio.session.nodeNum {
			await MeshPackets.shared.setRadioAutoConnect(nodeNum: nodeNum, false)
		}
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
			await disconnectAdditionalRadio(deviceId, byUser: true)
		}
	}

	// MARK: - Reconnect (T063)

	/// Keeps trying to reconnect a radio that dropped, until it's back, the user disconnects
	/// it, or it becomes the focused radio. Each attempt is bounded, so an out-of-range BLE radio
	/// doesn't hold the scan paused; attempts back off up to a minute.
	func scheduleAdditionalRadioReconnect(_ device: Device, firstDelay: Duration = .seconds(5)) {
		guard additionalRadioReconnects[device.id] == nil else { return }
		Logger.transport.info("🔗🔁 [Additional] Will reconnect \(device.name, privacy: .public) when it's back")
		additionalRadioReconnects[device.id] = Task { @MainActor [weak self] in
			var delay = firstDelay
			defer { self?.additionalRadioReconnects.removeValue(forKey: device.id) }
			while !Task.isCancelled {
				try? await Task.sleep(for: delay)
				guard let self, !Task.isCancelled else { return }
				if self.isRadioConnected(device.id) { return }
				// Wait for a focused radio and a free slot rather than taking over as the focused
				// radio, which is the preferred radio's own reconnect to make.
				if self.activeConnection != nil, self.canConnectAnotherRadio {
					do {
						try await self.connectAdditionalRadio(device, connectTimeout: Self.additionalReconnectTimeout)
						Logger.transport.info("🔗🔁 [Additional] Reconnected \(device.name, privacy: .public)")
						return
					} catch let error as AdditionalRadioNeedsFocusError {
						// Retrying can't fix it; the user has to focus it (to unlock or update it).
						Logger.transport.info("🔗🔁 [Additional] Stopped reconnecting \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
						return
					} catch {
						Logger.transport.info("🔗🔁 [Additional] Reconnect to \(device.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
					}
				}
				delay = min(max(delay, .seconds(5)) * 2, .seconds(60))
			}
		}
	}

	/// How long one automatic connect attempt waits for the transport.
	static let additionalReconnectTimeout: Duration = .seconds(20)

	// MARK: - Remembered radios (T063)

	/// After the focused radio connects, brings back the radios that were connected alongside
	/// it last time (`MyInfoEntity.autoConnect`). They go through the reconnect loop, so one
	/// that's out of range keeps being tried without blocking the others.
	func reconnectRememberedRadios() async {
		guard activeConnection != nil else { return }
		let connectedNums = Set(connectedRadios.compactMap(\.num))
		let remembered = await MeshPackets.shared.rememberedRadios(excluding: connectedNums)
		for radio in remembered {
			guard let device = device(for: radio), !isRadioConnected(device.id) else {
				Logger.transport.info("🔗🔁 [Additional] Can't bring back \(radio.name, privacy: .public) yet: not found on \(radio.transport.rawValue, privacy: .public)")
				continue
			}
			scheduleAdditionalRadioReconnect(device, firstDelay: .zero)
		}
	}

	/// A `Device` the transports can connect for a remembered radio: the discovered one, a saved
	/// manual (TCP) connection, or for BLE the peripheral id alone, which CoreBluetooth resolves
	/// without a scan.
	func device(for remembered: MeshPackets.RememberedRadio) -> Device? {
		guard let id = UUID(uuidString: remembered.peripheralId) else { return nil }
		if let discovered = devices.first(where: { $0.id == id }) {
			return discovered
		}
		if let manual = ManualConnectionList.shared.connectionsList.first(where: { $0.id == id }) {
			return manual
		}
		guard remembered.transport == .ble else { return nil }
		return Device(id: id, name: remembered.name, transportType: .ble, identifier: id.uuidString, num: remembered.nodeNum)
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
		case .error(let error):
			Logger.transport.error("🔗➕ [Additional] \(radio.session.device.name, privacy: .public) reported: \(error.localizedDescription, privacy: .public)")
			await disconnectAdditionalRadio(radio.id)
			scheduleAdditionalRadioReconnect(radio.session.device)
		case .errorWithoutReconnect(let error):
			Logger.transport.error("🔗➕ [Additional] \(radio.session.device.name, privacy: .public) reported: \(error.localizedDescription, privacy: .public)")
			await disconnectAdditionalRadio(radio.id)
		case .disconnected(let shouldReconnect):
			await disconnectAdditionalRadio(radio.id)
			if shouldReconnect {
				scheduleAdditionalRadioReconnect(radio.session.device)
			}
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

		case .lockdownStatus(let status):
			handleAdditionalLockdown(status, radio: radio)

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
