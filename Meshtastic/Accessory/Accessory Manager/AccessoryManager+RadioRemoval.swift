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
	/// connected. Focused, it first hands the focus to another connected radio, so it leaves as
	/// any additional radio does. With `reconnect` (a NodeDB or config reset: the radio reboots
	/// and comes back) it is tried again until it's back; without, it isn't remembered.
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
			let next = additionalRadios.values.first { canFocusWithoutReconnecting($0.device.id) }
			if let next, await focusConnectedRadio(next.device.id, previousStays: false) {
				Logger.transport.info("🔀 \(next.device.name, privacy: .public) takes the focus from \(device.name, privacy: .public), which is being reset or removed")
				if reconnect {
					// A reset radio comes back alongside, now and at the next launch.
					await MeshPackets.shared.setRadioAutoConnect(nodeNum: radioNum, true)
				}
			} else {
				// Nothing else can take the focus: the radio leaves as the only one did before.
				if reconnect {
					try? await session.connection.disconnect(withError: nil, shouldReconnect: true)
				} else {
					await MeshPackets.shared.setRadioAutoConnect(nodeNum: radioNum, false)
					try? await disconnect()
				}
				return
			}
		}
		await disconnectAdditionalRadio(device.id, byUser: !reconnect)
		if reconnect {
			scheduleAdditionalRadioReconnect(device)
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
			await disconnectAdditionalRadio(deviceId, byUser: true)
		}
	}

	/// Remove This Radio (D-18): disconnects `radioNum` without resetting it, and removes its
	/// data as a reset with messages deleted would, then forgets it.
	func removeRadio(_ radioNum: Int64) async {
		await takeRadioOffline(radioNum, reconnect: false)
		await MeshPackets.shared.flushDebouncedSaves()
		await MeshPackets.shared.removeRadioData(radioNum, .remove)
		if PreferredRadio.nodeNum == radioNum {
			if let focused = activeConnection?.device {
				PreferredRadio.set(focused)
			} else {
				PreferredRadio.peripheralId = ""
				PreferredRadio.nodeNum = 0
			}
		}
	}
}
