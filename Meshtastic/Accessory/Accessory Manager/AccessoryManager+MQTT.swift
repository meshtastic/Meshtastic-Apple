//
//  AccessoryManager+MQTT.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/18/25.
//

import Foundation
import CocoaMQTT
import OSLog
import MeshtasticProtobufs

extension AccessoryManager {

	func initializeMqtt() async {
		guard let deviceNum = activeConnection?.device.num else {
			Logger.services.error("Attempt to initialize MQTT without an active connection")
			return
		}

		let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(deviceNum))
		do {
			let fetchedNodeInfo = try context.fetch(fetchNodeInfoRequest)
			if fetchedNodeInfo.count == 1 {
				// Subscribe to Mqtt Client Proxy if enabled
				if fetchedNodeInfo[0].mqttConfig != nil && fetchedNodeInfo[0].mqttConfig?.enabled ?? false && fetchedNodeInfo[0].mqttConfig?.proxyToClientEnabled ?? false {
					mqttManager.connectFromConfigSettings(node: fetchedNodeInfo[0])
				} else {
					if mqttProxyConnected {
						mqttManager.mqttClientProxy?.disconnect()
					}
				}
				// Set initial unread message badge states
				appState.unreadChannelMessages = fetchedNodeInfo[0].myInfo?.unreadMessages(context: context) ?? 0
				appState.unreadDirectMessages = fetchedNodeInfo[0].user?.unreadMessages(context: context, skipLastMessageCheck: true) ?? 0 // skipLastMessageCheck=true because we don't update lastMessage on our own connected node
			}
			if fetchedNodeInfo.count == 1 && fetchedNodeInfo[0].rangeTestConfig?.enabled == true {
				wantRangeTestPackets = true
			}
			if fetchedNodeInfo.count == 1 && fetchedNodeInfo[0].storeForwardConfig?.enabled == true {
				wantStoreAndForwardPackets = true
			}
		} catch {
			Logger.data.error("Failed to find a node info for the connected node \(error.localizedDescription, privacy: .public)")
		}

	}

	// MARK: MqttClientProxyManagerDelegate Methods
	func onMqttConnected() {
		mqttProxyConnected = true
		mqttError = ""
		Logger.services.info("📲 [MQTT Client Proxy] onMqttConnected now subscribing to \(self.mqttManager.topic, privacy: .public).")
		mqttManager.mqttClientProxy?.subscribe(mqttManager.topic)
	}

	func onMqttDisconnected() {
		mqttProxyConnected = false
		Logger.services.info("📲 MQTT Disconnected")
	}

	func onMqttMessageReceived(message: CocoaMQTTMessage) {
		if message.topic.contains("/stat/") {
			return
		}
		var proxyMessage = MqttClientProxyMessage()
		proxyMessage.topic = message.topic
		proxyMessage.data = Data(message.payload)
		proxyMessage.retained = message.retained

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.mqttClientProxyMessage = proxyMessage
		Task {
			try? await self.send(toRadio)
		}
	}

	func onMqttError(message: String) {
		mqttProxyConnected = false
		mqttError = message
		Logger.services.info("📲 [MQTT Client Proxy] onMqttError: \(message, privacy: .public)")
	}
}
