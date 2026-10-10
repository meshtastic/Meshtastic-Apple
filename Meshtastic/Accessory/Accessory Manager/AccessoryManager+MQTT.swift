//
//  AccessoryManager+MQTT.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/18/25.
//

import Foundation
import CocoaMQTT
import OSLog
@preconcurrency import SwiftData
import MeshtasticProtobufs

// Serialises MQTT-sourced BLE writes by allowing at most one forwarded packet
// in-flight over BLE at any time. CocoaMQTT delivers its delegate callbacks on
// its default `delegateQueue` (DispatchQueue.main) and we never override it, so
// the receive handler runs on the main actor; each forward still kicks off an
// async BLE write, and this actor gates entry and drops packets that arrive
// while a write is already in progress rather than queuing them, preventing the
// device firmware from being overwhelmed by global broker traffic.
actor MqttForwardGate {
	private var busy = false

	// Returns true if the caller should proceed, false if it should drop the packet.
	func tryAcquire() -> Bool {
		guard !busy else { return false }
		busy = true
		return true
	}

	func release() {
		busy = false
	}
}

extension AccessoryManager {

	/// Connect Step 8 for the first radio: the unread badges. Its MQTT client proxy starts
	/// like every radio's (`startMqtt`, `AccessoryManager+RadioMQTT.swift`).
	func initializeUnreadBadges() {
		guard let deviceNum = activeConnection?.device.num else {
			Logger.services.error("Attempt to set the unread badges without an active connection")
			return
		}

		let nodeNum = Int64(deviceNum)
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == nodeNum }
		)
		do {
			let fetchedNodeInfo = try context.fetch(descriptor)
			if fetchedNodeInfo.count == 1 {
				// Set initial unread message badge states
				appState.unreadChannelMessages = fetchedNodeInfo[0].myInfo?.unreadMessages(context: context) ?? 0
				// Feature 021 (T090): direct messages to every radio count towards the badge.
				var radios = UserEntity.localRadioNums(context: context)
				radios.insert(fetchedNodeInfo[0].num)
				appState.unreadDirectMessages = UserEntity.unreadDirectMessages(toRadios: radios, context: context)
			}
		} catch {
			Logger.data.error("Failed to find a node info for the connected node \(error.localizedDescription, privacy: .public)")
		}
	}

	/// The first radio's MQTT client proxy state, for the MQTT icon (T071c).
	var mqttProxyConnected: Bool { activeConnection?.mqtt?.isConnected ?? false }
	var mqttError: String { activeConnection?.mqtt?.errorMessage ?? "" }
	var mqttTopics: [String] { activeConnection?.mqtt?.topics ?? [] }
}
