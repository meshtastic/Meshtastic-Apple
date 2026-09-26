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

	// One shared gate — drops concurrent MQTT→BLE writes instead of queuing them.
	static let mqttForwardGate = MqttForwardGate()

	func initializeMqtt() async {
		guard let deviceNum = activeConnection?.device.num else {
			Logger.services.error("Attempt to initialize MQTT without an active connection")
			return
		}

		let nodeNum = Int64(deviceNum)
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == nodeNum }
		)
		do {
			let fetchedNodeInfo = try context.fetch(descriptor)
			if fetchedNodeInfo.count == 1 {
				// Subscribe to Mqtt Client Proxy if enabled
				if fetchedNodeInfo[0].mqttConfig != nil && fetchedNodeInfo[0].mqttConfig?.enabled ?? false && fetchedNodeInfo[0].mqttConfig?.proxyToClientEnabled ?? false {
					// Brief delay so CFNetwork callbacks don't fire before the app is fully
					// initialised — prevents a launch-time SIGABRT in CocoaMQTT's stream parser.
					try? await Task.sleep(for: .seconds(1))
					mqttManager.connectFromConfigSettings(node: fetchedNodeInfo[0])
				} else {
					if mqttProxyConnected {
						mqttManager.mqttClientProxy?.disconnect()
					}
				}
				// Set initial unread message badge states
				appState.unreadChannelMessages = fetchedNodeInfo[0].myInfo?.unreadMessages(context: context) ?? 0
				// Feature 021 (T090): direct messages to every radio count towards the badge.
				var radios = UserEntity.localRadioNums(context: context)
				radios.insert(fetchedNodeInfo[0].num)
				appState.unreadDirectMessages = UserEntity.unreadDirectMessages(toRadios: radios, context: context)

				// Set wantRangeTestPackets and wantStoreAndForwardPackets
				wantRangeTestPackets = fetchedNodeInfo[0].rangeTestConfig?.enabled ?? false
				wantStoreAndForwardPackets = fetchedNodeInfo[0].storeForwardConfig?.enabled ?? false
			}
		} catch {
			Logger.data.error("Failed to find a node info for the connected node \(error.localizedDescription, privacy: .public)")
		}

	}

	// MARK: MqttClientProxyManagerDelegate Methods
	func onMqttConnected() {
		mqttProxyConnected = true
		mqttError = ""
		for topic in mqttManager.topics {
			Logger.services.info("📲 [MQTT Client Proxy] onMqttConnected subscribing to \(topic, privacy: .public).")
			mqttManager.mqttClientProxy?.subscribe(topic, qos: .qos1)
		}
		if mqttManager.topics.isEmpty {
			Logger.services.info("📲 [MQTT Client Proxy] onMqttConnected - no topics to subscribe to")
		}
	}

	func onMqttDisconnected() {
		mqttProxyConnected = false
		Logger.services.info("📲 MQTT Disconnected")
	}

	func onMqttMessageReceived(message: CocoaMQTTMessage) {
		// Drops provably-undeliverable packets before spending any BLE bandwidth on them, and
		// clamps the hop limit to 0 (`MqttProxyPackets.downlink`).
		let toRadio: ToRadio
		switch MqttProxyPackets.downlink(topic: message.topic, payload: Data(message.payload), retained: message.retained, myNodeNum: myNodeNum) {
		case .dropStat:
			Logger.services.debug("📲 [MQTT] dropping /stat/ message on \(message.topic, privacy: .public)")
			return
		case .dropNoPayload:
			mqttProxyDroppedNoPayload += 1
			Logger.services.debug("📲 [MQTT] drop (no payload) topic=\(message.topic, privacy: .public) count=\(self.mqttProxyDroppedNoPayload, privacy: .public)")
			return
		case .forward(let packet, let zeroedHopLimit):
			toRadio = packet
			if let zeroedHopLimit {
				Logger.services.info("📲 [MQTT] forwarding \(message.topic, privacy: .public) — zeroed hop_limit \(zeroedHopLimit, privacy: .public)→0 bytes=\(message.payload.count, privacy: .public)")
			} else {
				Logger.services.info("📲 [MQTT] forwarding \(message.topic, privacy: .public) — hop_limit already 0 or non-envelope bytes=\(message.payload.count, privacy: .public)")
			}
		}

		// Gate: drop this packet if a previous MQTT→BLE write is still in-flight.
		// The public broker can deliver global LongFast traffic faster than BLE can
		// drain it. Queuing every packet would overwhelm the device's radio stack;
		// dropping excess is preferable to building an unbounded BLE write backlog.
		Task {
			let gate = AccessoryManager.mqttForwardGate
			guard await gate.tryAcquire() else {
				Logger.services.debug("📲 [MQTT] drop (BLE write in-flight): \(message.topic, privacy: .public)")
				return
			}
			defer { Task { await gate.release() } }
			try? await self.send(toRadio)
		}
	}

	func onMqttError(message: String) {
		mqttProxyConnected = false
		mqttError = message
		Logger.services.info("📲 [MQTT Client Proxy] onMqttError: \(message, privacy: .public)")
	}
}
