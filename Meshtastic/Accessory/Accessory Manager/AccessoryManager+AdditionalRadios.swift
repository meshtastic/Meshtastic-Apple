//
//  AccessoryManager+AdditionalRadios.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs
import OSLog

// MARK: - Radios connected alongside the first one (feature 021)

// Every connected radio is a `RadioSession` and runs the same connect steps (D-17, plan.md ›
// Every radio the same). The one connected first is `AccessoryManager.activeConnection`; the
// others are in `additionalRadios`, by device id. This file keeps track of the others: which are
// connected, their events, disconnecting and reconnecting them, and the radios remembered from
// last time. A radio that's locked or needs a firmware update is asked about in
// `AccessoryManager+RadioAttention.swift`.

/// Lets one radio at a time run its config and node-DB handshake (T064).
///
/// Two dumps at once double the ingest load, and the first radio's connect recycles the
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

extension AccessoryManager {

	/// At most this many radios at once, the first one included (D-10).
	static let maxConnectedRadios = 4

	/// Radios connected now: the first one plus the additional ones.
	var connectedRadioCount: Int {
		(activeConnection == nil ? 0 : 1) + additionalRadios.count
	}

	/// A radio is connected, or the first one is connecting, for another to connect alongside
	/// (review V11 W2). With none, a connect is the first radio's.
	var hasRadioToJoin: Bool {
		connectedRadioCount > 0 || hasFirstConnectInProgress
	}

	var canConnectAnotherRadio: Bool {
		connectedRadioCount < Self.maxConnectedRadios
	}

	/// True when `deviceId` is connected or connecting, the first radio or another.
	func isRadioConnected(_ deviceId: UUID) -> Bool {
		activeConnection?.device.id == deviceId || additionalRadios[deviceId] != nil || connectAttempts[deviceId] != nil
	}

	/// Every connected radio's device, starting with the first radio.
	var connectedRadios: [Device] {
		var result: [Device] = []
		if let first = activeConnection?.device { result.append(first) }
		return result + additionalRadioDevices
	}

	/// Adds `device` alongside the connected radios (W-12): the others stay connected. The caller
	/// shows it (`selectWindowRadio`): the one window switches to it on iPhone and iPad; on the Mac
	/// it opens in its own window once connected. Throws when it can't connect.
	func addRadio(_ device: Device) async throws {
		try await connectAdditionalRadio(device)
	}

	/// Disconnects radio `deviceId` for the user, the first radio or another (D-19): it isn't
	/// brought back, and its window on the Mac closes (W-02). Without the first radio the others
	/// stay connected and none takes its place (T316).
	func disconnectRadio(_ deviceId: UUID) async {
		if activeConnection?.device.id == deviceId || connectAttempts[deviceId]?.isFirst == true {
			try? await disconnectFirstRadio(accessoryManager: self)
		} else {
			await disconnectAdditionalRadio(deviceId, byUser: true)
		}
	}

	/// Fills `knownNodeNums` from the store's radios, at launch (review V11 W7).
	func seedKnownNodeNums() async {
		for (peripheralId, nodeNum) in await MeshPackets.shared.radioPeripheralIds() {
			if let id = UUID(uuidString: peripheralId), knownNodeNums[id] == nil {
				knownNodeNums[id] = nodeNum
			}
		}
	}

	/// Releases radio `deviceId` for a firmware update (review V11 W1): its link closes so the
	/// updater can reach it in update mode. Its window stays, it stays remembered, and the other
	/// radios are left as they are. `reclaimRadioAfterUpdate(_:)` brings it back.
	func releaseRadioForUpdate(_ deviceId: UUID) async throws {
		if activeConnection?.device.id == deviceId {
			try await disconnect(forUpdate: true)
		} else {
			await disconnectAdditionalRadio(deviceId, forUpdate: true)
		}
	}

	/// After a firmware update of `device`: the preferred radio comes back through discovery, as a
	/// single radio does (the updater restarts it); another through its reconnect.
	func reclaimRadioAfterUpdate(_ device: Device) {
		guard device.id.uuidString != PreferredRadio.peripheralId, !isRadioConnected(device.id) else { return }
		scheduleAdditionalRadioReconnect(device)
	}

	/// The Disconnect command for radio `radioNum` (T320): the radio connected first disconnects
	/// as it always has; another as Disconnect on its row does.
	func disconnectRadio(nodeNum radioNum: Int64) async throws {
		guard let session = connectedSession(forRadio: radioNum) else { return }
		if session === activeConnection {
			try await disconnect()
		} else {
			await disconnectAdditionalRadio(session.device.id, byUser: true)
		}
	}

	/// Whether `session` is the only radio connected: a connect that does the app's own work
	/// (device catalog, stale-node prune, unread badges, T309) is one with no other radio connected.
	/// With one radio that's every connect, as before.
	func isOnlyConnectedRadio(_ session: RadioSession?) -> Bool {
		guard let session else { return false }
		return (activeConnection == nil || activeConnection === session)
			&& additionalRadios.values.allSatisfy { $0 === session }
	}

	/// The additional radios' devices, by name.
	var additionalRadioDevices: [Device] {
		additionalRadios.values
			.map(\.device)
			.sorted { ($0.longName ?? $0.name) < ($1.longName ?? $1.name) }
	}

	/// `session` when it's one of the radios connected alongside the first one.
	func additionalRadio(for session: RadioSession) -> RadioSession? {
		additionalRadios[session.device.id].flatMap { $0 === session ? $0 : nil }
	}

	// MARK: - Connect

	/// Connects `device` alongside the first radio, through the same connect steps as the
	/// first one (D-17). With no radio connected this is a normal connect, and the radio becomes
	/// the first one. `connectTimeout` bounds the transport connect for automatic attempts; a
	/// user's tap waits as long as the transport does. Throws when the radio didn't connect.
	func connectAdditionalRadio(_ device: Device, connectTimeout: Duration? = nil) async throws {
		// With the first radio gone and others connected, it joins them; it doesn't take the first
		// radio's place, which stays the preferred radio's (review V11 W3).
		guard hasRadioToJoin else {
			try await connect(to: device)
			return
		}
		guard !isRadioConnected(device.id) else {
			throw AccessoryError.connectionFailed("This radio is already connected")
		}
		guard canConnectAnotherRadio else {
			throw AccessoryError.connectionFailed(String.localizedStringWithFormat("You can connect up to %d radios at once.".localized, Self.maxConnectedRadios))
		}
		Logger.transport.info("🔗➕ [Additional] Connecting \(device.name, privacy: .public) alongside \(self.activeConnection?.device.name ?? "?", privacy: .public)")
		try await connect(to: device, asFirst: false, connectTimeout: connectTimeout)
		Logger.transport.info("🔗➕ [Additional] \(device.name, privacy: .public) connected; \(self.connectedRadioCount) radios connected")
	}

	/// `transport.connect(to:)`, given up after `timeout` when there is one. A BLE connect to an
	/// out-of-range radio otherwise waits indefinitely, holding the scan paused.
	func connectTransport(_ transport: any Transport, to device: Device, within timeout: Duration?) async throws -> any Connection {
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

	/// Runs the backfill for rows from before feature 021 when radio `radioNum` reports itself and
	/// isn't the radio those rows belong to (`BackfillOwner`), the first radio or another: a radio added
	/// alongside, or one the user switched to (T186, T193). Run by connect Step 3c, once the
	/// config is in and before the radio's node DB, and matched by node number (T203): a
	/// peripheral id changes on a new phone, a node number doesn't. The store's own radio doesn't
	/// wait for it, so a single-radio user's connect doesn't either. Its connect holds the
	/// handshake gate, so no node dump runs meanwhile, and the drain lets packets through between
	/// chunks. `othersObserved` is what its connect found before the radio's first packet (T230).
	func backfillBeforeAnotherRadioJoins(radioNum: Int64, name: String, othersObserved: Bool? = nil) async {
		let packets = MeshPackets.shared
		guard await packets.hasPendingBackfill() else {
			BackfillOwner.clear()
			return
		}
		let owner = BackfillOwner.current()
		guard owner.nodeNum != 0, radioNum != owner.nodeNum else { return }
		do {
			let filled = try await packets.drainMultiRadioBackfill(ownRadio: owner.nodeNum, othersObserved: othersObserved)
			Logger.data.info("🧭 [MultiRadio] Backfilled \(filled) rows for \(owner.nodeNum.toHex(), privacy: .public) before \(name, privacy: .public) joined")
			if await !packets.hasPendingBackfill() {
				BackfillOwner.clear()
			}
		} catch {
			Logger.data.error("💥 [MultiRadio] Backfill before \(name, privacy: .public) joined failed: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// A BLE restore (T190): the radios restored alongside the first one are remembered, so the
	/// remembered-radio reconnect after its connect claims them. Each comes back as it was; none
	/// takes another's place (D-19).
	func noteRestoredAlongside(peripheralIds: [UUID]) async {
		await MeshPackets.shared.rememberRadios(peripheralIds: peripheralIds.map(\.uuidString))
	}

	// MARK: - Disconnect

	/// Disconnects one additional radio. The first radio and the others are unaffected.
	/// `byUser` also stops any automatic reconnect for it, now and at the next launch.
	func disconnectAdditionalRadio(_ deviceId: UUID, byUser: Bool = false, forUpdate: Bool = false) async {
		// Its window on the Mac closes once it's disconnected (W-02); not when it's only released
		// for a firmware update, which also keeps it remembered (review V11 W1).
		defer {
			if byUser, !forUpdate { radioDisconnectedByUser.send(deviceId) }
		}
		if byUser || forUpdate {
			additionalRadioReconnects.removeValue(forKey: deviceId)?.cancel()
			awaitedRememberedRadios.remove(deviceId)
			radioConnectErrors.removeValue(forKey: deviceId)
		}
		// A connect still in progress for it stops, whether it's waiting for the handshake gate
		// or running its steps.
		if let attempt = connectAttempts[deviceId], !attempt.isFirst {
			attempt.isCancelled = true
			await attempt.stepper?.cancelCurrentlyExecutingStep(withError: AccessoryError.disconnected("Radio disconnected"), cancelFullProcess: true)
		}
		guard let session = additionalRadios.removeValue(forKey: deviceId) else {
			if connectAttempts[deviceId] != nil {
				updateDevice(deviceId: deviceId, key: \.connectionState, value: .disconnected)
			}
			return
		}
		if byUser, !forUpdate, let nodeNum = session.nodeNum {
			await MeshPackets.shared.setRadioAutoConnect(nodeNum: nodeNum, false)
		}
		retiredAdditionalSessionIDs.insert(session.id)
		await MeshPackets.shared.flushDebouncedSaves()
		await tearDown(session)
		try? await session.connection.disconnect(withError: nil, shouldReconnect: false)
		updateDevice(deviceId: deviceId, key: \.connectionState, value: .disconnected)
		Logger.transport.info("🔗➖ [Additional] Disconnected \(session.device.name, privacy: .public); \(self.connectedRadioCount) radios connected")
	}

	func disconnectAllAdditionalRadios() async {
		for deviceId in Array(additionalRadios.keys) {
			await disconnectAdditionalRadio(deviceId, byUser: true)
		}
	}

	// MARK: - Reconnect (T063)

	/// Keeps trying to reconnect a radio that dropped, until it's back, the user disconnects
	/// it, or it becomes the first radio. Each attempt is bounded, so an out-of-range BLE radio
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
				// Wait for a radio to join and a free slot rather than taking over as the first
				// radio, which is the preferred radio's own reconnect to make.
				if self.hasRadioToJoin, self.canConnectAnotherRadio {
					do {
						try await self.connectAdditionalRadio(device, connectTimeout: Self.additionalReconnectTimeout)
						Logger.transport.info("🔗🔁 [Additional] Reconnected \(device.name, privacy: .public)")
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

	/// After the first radio connects, brings back the radios that were connected alongside
	/// it last time (`MyInfoEntity.autoConnect`). They go through the reconnect loop, so one
	/// that's out of range keeps being tried without blocking the others.
	func reconnectRememberedRadios() async {
		guard connectedRadioCount > 0 else { return }
		let connectedNums = Set(connectedRadios.compactMap(\.num))
		let remembered = await MeshPackets.shared.rememberedRadios(excluding: connectedNums)
		for radio in remembered {
			guard let device = device(for: radio) else {
				Logger.transport.info("🔗🔁 [Additional] Can't bring back \(radio.name, privacy: .public) yet: not found on \(radio.transport.rawValue, privacy: .public); waiting for discovery to see it")
				if let id = UUID(uuidString: radio.peripheralId) {
					awaitedRememberedRadios.insert(id)
				}
				continue
			}
			guard !isRadioConnected(device.id) else { continue }
			scheduleAdditionalRadioReconnect(device, firstDelay: .zero)
		}
	}

	/// A `Device` the transports can connect for a remembered radio: the discovered one, a saved
	/// manual (TCP) connection, or for BLE the peripheral id alone, which CoreBluetooth resolves
	/// without a scan.
	func device(for remembered: MeshPackets.RememberedRadio) -> Device? {
		guard let id = UUID(uuidString: remembered.peripheralId) else { return nil }
		if let discovered = devices.first(where: { $0.id == id }) ?? recentlyDiscoveredDevices[id] {
			return discovered
		}
		if let manual = ManualConnectionList.shared.connectionsList.first(where: { $0.id == id }) {
			return manual
		}
		guard remembered.transport == .ble else { return nil }
		return Device(id: id, name: remembered.name, transportType: .ble, identifier: id.uuidString, num: remembered.nodeNum)
	}

	// MARK: - Events

	/// Handles one event from a radio connected alongside the first one. Its data takes the
	/// same path as the first radio's (`processFromRadio`, scoped to the session). An error or a
	/// disconnect ends only this radio: a connect in progress retries or gives up as the first
	/// radio's would, and a connected radio is disconnected and, unless told otherwise,
	/// reconnected when it's back.
	func didReceiveAdditional(_ event: ConnectionEvent, session: RadioSession) async {
		switch event {
		case .data(let fromRadio):
			await processFromRadio(fromRadio, session: session)
			await noteIngestedPacket()
			Task {
				await session.heartbeatResponseTimer?.cancel(withReason: "Data packet received")
				await session.heartbeatTimer?.reset(delay: .seconds(Self.heartbeatInterval))
			}
		case .logMessage(let message):
			didReceiveLog(message: message)
			Task {
				await session.heartbeatResponseTimer?.cancel(withReason: "Log message packet received")
				await session.heartbeatTimer?.reset(delay: .seconds(Self.heartbeatInterval))
			}
		case .rssiUpdate(let rssi):
			updateDevice(deviceId: session.device.id, key: \.rssi, value: rssi)
		case .error(let error), .errorWithoutReconnect(let error):
			Logger.transport.error("🔗➕ [Additional] \(session.device.name, privacy: .public) reported: \(error.localizedDescription, privacy: .public)")
			let reconnect: Bool
			if case .errorWithoutReconnect = event { reconnect = false } else { reconnect = true }
			if let attempt = connectAttempts[session.device.id], attempt.session === session, let stepper = attempt.stepper {
				await stepper.cancelCurrentlyExecutingStep(withError: error, cancelFullProcess: !reconnect)
				return
			}
			await disconnectAdditionalRadio(session.device.id)
			if reconnect {
				scheduleAdditionalRadioReconnect(session.device)
			}
		case .disconnected(let shouldReconnect):
			if let attempt = connectAttempts[session.device.id], attempt.session === session, let stepper = attempt.stepper {
				await stepper.cancelCurrentlyExecutingStep(withError: AccessoryError.disconnected("Radio disconnected"), cancelFullProcess: !shouldReconnect)
				return
			}
			await disconnectAdditionalRadio(session.device.id)
			if shouldReconnect {
				scheduleAdditionalRadioReconnect(session.device)
			}
		}
	}
}
