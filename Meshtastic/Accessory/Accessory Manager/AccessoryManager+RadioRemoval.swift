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
			}
			return
		}
		let device = session.device
		if session === activeConnection {
			let next = additionalRadios.values.first { canFocusWithoutReconnecting($0.device.id) }
			if let next, await focusConnectedRadio(next.device.id) {
				Logger.transport.info("🔀 \(next.device.name, privacy: .public) takes the focus from \(device.name, privacy: .public), which is being reset or removed")
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
