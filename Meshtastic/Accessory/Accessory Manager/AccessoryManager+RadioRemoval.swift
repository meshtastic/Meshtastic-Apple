//
//  AccessoryManager+RadioRemoval.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import OSLog

// MARK: - Resetting or removing one of several radios (feature 021, D-18, T147)

extension AccessoryManager {

	/// Disconnects radio `radioNum` for a reset or a removal while the other radios stay
	/// connected, as they are. With `reconnect` (a NodeDB or config reset: the radio reboots and
	/// comes back) it is tried again until it's back; without, it isn't remembered.
	func takeRadioOffline(_ radioNum: Int64, reconnect: Bool) async {
		guard let session = connectedSession(forRadio: radioNum) else {
			if !reconnect {
				await MeshPackets.shared.setRadioAutoConnect(nodeNum: radioNum, false)
				await stopBringingBack(radioNum)
			}
			return
		}
		let device = session.device
		if session === activeConnection {
			// It leaves as a single radio does; the other radios stay as they are (D-19).
			if reconnect {
				try? await session.connection.disconnect(withError: nil, shouldReconnect: true)
			} else {
				// A stand-in still connecting puts the preferred radio back, as Disconnect does
				// (review V18 D1).
				let standIn = standIn(for: device.id)
				await MeshPackets.shared.setRadioAutoConnect(nodeNum: radioNum, false)
				try? await disconnect()
				restorePreferred(after: standIn)
			}
			return
		}
		await disconnectAdditionalRadio(device.id, byUser: !reconnect)
		if reconnect {
			scheduleAdditionalRadioReconnect(device)
		}
	}

	/// After a factory reset that also cleared radio `radioNum`'s Bluetooth bonds (Delete all
	/// config, keys and BLE bonds), the only radio or one of several: it reboots and can't
	/// reconnect, so it's disconnected for the user whichever radio it is, the first radio or one
	/// alongside, and nothing brings it back (review V30-1, V31-1); `disconnect()` alone only acts
	/// on the first radio. Its window is told, so it stays on it, as for a Disconnect.
	///
	/// As on `main`, the preferred radio's Disconnect also runs when its link dropped already as it
	/// reset (the firmware turns Bluetooth off), so discovery doesn't connect it again. With another
	/// radio connected, that one becomes the preferred radio, as after Disconnect on the first
	/// radio (review V12 Y3), so the next launch doesn't wait for this one.
	func disconnectAfterFactoryReset(_ radioNum: Int64) async {
		await takeRadioOffline(radioNum, reconnect: false)
		guard activeConnection == nil, PreferredRadio.nodeNum == radioNum else { return }
		if !userRequestedConnectionCancellation {
			try? await disconnect()
		}
		if let other = connectedRadioAfterFirst {
			PreferredRadio.set(other)
		}
	}

	/// Stops everything that would bring back radio `radioNum`, which isn't connected (T191): its
	/// reconnect loop, a wait for discovery to see it, and a connect in progress, as Disconnect
	/// does for a connected radio. Found by its peripheral id and by any attempt for its number.
	func stopBringingBack(_ radioNum: Int64) async {
		var deviceIds = Set(connectAttempts.values.filter { $0.device.num == radioNum || $0.session?.nodeNum == radioNum }.map(\.device.id))
		if let peripheralId = await MeshPackets.shared.peripheralId(ofRadio: radioNum), let id = UUID(uuidString: peripheralId) {
			deviceIds.insert(id)
		}
		for deviceId in deviceIds {
			// A connect of it as the first radio, which discovery starts when nothing else is
			// connected (T360), is cancelled as Disconnect cancels it (review V15 Q1).
			if connectAttempts[deviceId]?.isFirst == true {
				let standIn = standIn(for: deviceId)
				try? await disconnect()
				restorePreferred(after: standIn)
			}
			await disconnectAdditionalRadio(deviceId, byUser: true)
		}
	}

	/// Remove Radio (D-18): disconnects `radioNum` without resetting it, removes its data and
	/// forgets it, and its window closes (W-02). With other radios' data in the store only its own
	/// goes, as a reset with messages deleted would. As the only radio the app knows its data is
	/// the whole store, which clears as a single radio's reset does, favorites kept.
	///
	/// One removal of a radio at a time, and nothing connects it meanwhile (review V27-1, V27-2).
	/// Its data goes under the handshake gate, where whether the store clears is decided.
	func removeRadio(_ radioNum: Int64) async {
		guard radioNum != 0, !radiosBeingRemoved.contains(radioNum) else { return }
		var deviceIds = Set(knownNodeNums.filter { $0.value == radioNum }.map(\.key))
			.union([connectedSession(forRadio: radioNum)?.device.id].compactMap { $0 })
			.union(connectAttempts.values.filter { $0.device.num == radioNum || $0.session?.nodeNum == radioNum }.map(\.device.id))
		if PreferredRadio.nodeNum == radioNum, let preferred = UUID(uuidString: PreferredRadio.peripheralId) {
			deviceIds.insert(preferred)
		}
		let wasConnected = connectedSession(forRadio: radioNum) != nil
		// Whose the store's rows from before feature 021 are, before the preferred radio moves on.
		let backfillOwner = BackfillOwner.current().nodeNum
		radiosBeingRemoved.insert(radioNum)
		deviceIdsBeingRemoved.formUnion(deviceIds)
		defer {
			radiosBeingRemoved.remove(radioNum)
			deviceIdsBeingRemoved.subtract(deviceIds)
		}
		if let peripheralId = await MeshPackets.shared.peripheralId(ofRadio: radioNum), let id = UUID(uuidString: peripheralId) {
			deviceIds.insert(id)
			deviceIdsBeingRemoved.insert(id)
		}
		await takeRadioOffline(radioNum, reconnect: false)
		radiosReleasedForUpdate.subtract(deviceIds)
		// Its windows close before its data goes.
		for deviceId in deviceIds.sorted(by: { $0.uuidString < $1.uuidString }) {
			knownNodeNums.removeValue(forKey: deviceId)
			radioRemoved.send(deviceId)
		}
		// Handed on before its data is cleaned up, so what's kept goes to the new preferred radio
		// (review V13 R13-2): the first radio, or with it removed another connected radio, as
		// Disconnect on the first radio does (T352, review V13 Z2). After `takeRadioOffline`, so
		// a stand-in's preferred radio is put back first (`restorePreferred`); the radio can't
		// come back meanwhile, as `connect(to:)` refuses it.
		if PreferredRadio.nodeNum == radioNum {
			if let next = activeConnection?.device ?? connectedRadioAfterFirst {
				PreferredRadio.set(next)
			} else {
				PreferredRadio.peripheralId = ""
				PreferredRadio.nodeNum = 0
			}
		}
		if await removeData(ofRemovedRadio: radioNum, wasConnected: wasConnected, backfillOwner: backfillOwner) {
			// As Clear App Data does: no reconnect follows to refill the device catalog (review V27-9).
			clearNotifications()
			try? await MeshtasticAPI.shared.refreshBundledDevicesData()
		}
		// A service that used it asks for another when several radios remain (W-15).
		clearServiceRadios(pointingAt: radioNum)
		await refreshKnownRadios()
	}

	/// Removes the data of `radioNum`, which is offline now, holding the handshake gate (review
	/// V27-1): no radio's handshake writes meanwhile, and the launch backup merge isn't between
	/// chunks. Whether the store clears is decided here, from what's connected, connecting and
	/// stored now; a radio connecting from now on waits at the gate and finds the fresh store.
	/// Returns whether the store was cleared.
	private func removeData(ofRemovedRadio radioNum: Int64, wasConnected: Bool, backfillOwner: Int64) async -> Bool {
		await handshakeGate.acquire()
		defer { handshakeGate.release() }
		let packets = MeshPackets.shared
		await packets.flushDebouncedSaves()
		let storedRadios = await packets.storedRadios().map(\.nodeNum)
		let othersHoldData = await packets.holdsUncountedData(ofRadiosOtherThan: radioNum, backfillOwner: backfillOwner)
		let ownsPendingBackfill = await packets.ownsPendingBackfill(radioNum, backfillOwner: backfillOwner)
		let clearsStore = Self.removalClearsStore(
			radioNum,
			storedRadios: storedRadios,
			wasConnected: wasConnected,
			ownsPendingBackfill: ownsPendingBackfill,
			otherRadioActive: connectedRadioCount > 0 || !connectAttempts.isEmpty,
			othersHoldData: othersHoldData
		)
		guard clearsStore else {
			await packets.removeRadioData(radioNum, .remove)
			return false
		}
		let cleared = await packets.clearDatabase(includeRoutes: false, preserveFavorites: true)
		await resetDatabaseAfterClear()
		if !cleared {
			// Stopped part-way, so its MyInfo may be left (review V27-9): its own data goes as with
			// other radios' data in the store, on the fresh store's actor.
			Logger.data.error("💥 [MultiRadio] Clearing the store for removed radio \(radioNum.toHex(), privacy: .public) stopped part-way; removing its own data instead")
			await MeshPackets.shared.removeRadioData(radioNum, .remove)
		}
		return true
	}

	/// Whether Remove Radio is offered for radio `radioNum` (D-18): it's connected with its
	/// handshake done, or it's off, and it isn't being removed already (review V27-2, V27-5). Not
	/// while it connects, as in Your Radios (T197): a packet of its handshake could land after
	/// its data is gone.
	func canRemoveRadio(_ radioNum: Int64) -> Bool {
		guard radioNum != 0, !radiosBeingRemoved.contains(radioNum) else { return false }
		return !connectAttempts.values.contains { attempt in
			attempt.device.num == radioNum || attempt.session?.nodeNum == radioNum || knownNodeNums[attempt.device.id] == radioNum
		}
	}

	/// Whether removing `radioNum` clears the store (D-18): nothing else is in it, by
	/// `storedRadios` and by what that doesn't count (`othersHoldData`, review V27-3), and no
	/// other radio is connected or connecting (`otherRadioActive`). `removeRadioData` would leave
	/// what a single radio stored before feature 021, which has no radio recorded on it.
	///
	/// A radio the store doesn't have that wasn't connected (a ghost after Clear App Data or a
	/// restore) is only forgotten (review V27-4): clearing would only recreate the container.
	/// The store has the radio when `storedRadios` counts it, when it was connected (still in its
	/// first download it has stored nothing yet), or when the store's rows from before feature 021
	/// are its own and wait for the backfill (`ownsPendingBackfill`, review V28-3): before its
	/// first connect since the update `storedRadios` doesn't count it.
	// swiftlint:disable:next function_parameter_count
	nonisolated static func removalClearsStore(
		_ radioNum: Int64,
		storedRadios: [Int64],
		wasConnected: Bool,
		ownsPendingBackfill: Bool,
		otherRadioActive: Bool,
		othersHoldData: Bool
	) -> Bool {
		guard !otherRadioActive, !othersHoldData, !storedRadios.contains(where: { $0 != radioNum }) else { return false }
		return wasConnected || ownsPendingBackfill || storedRadios.contains(radioNum)
	}
}
