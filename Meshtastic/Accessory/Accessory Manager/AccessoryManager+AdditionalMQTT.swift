//
//  AccessoryManager+AdditionalMQTT.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import CocoaMQTT
import Foundation
import MeshtasticProtobufs
import OSLog
@preconcurrency import SwiftData

/// The MQTT client proxy for one radio connected alongside the focused one (feature 021, T100).
///
/// A radio with MQTT "proxy to client" on has no internet of its own and relies on the phone to
/// reach the broker. The focused radio keeps `MqttClientProxyManager.shared`; each additional
/// radio gets its own proxy instance, broker client and forward gate, built from its own MQTT
/// config and channels, so its uplink and downlink never mix with another radio's.
///
/// `@preconcurrency`: CocoaMQTT calls its delegate on the main queue (its default
/// `delegateQueue`, never overridden), which the runtime isolation check confirms.
@MainActor
final class AdditionalRadioMqttBridge: @preconcurrency MqttClientProxyManagerDelegate {
	let proxy: MqttClientProxyManager
	private weak var radio: AdditionalRadio?
	/// One broker-to-radio write at a time; extra packets are dropped, like the focused radio's.
	private let forwardGate = MqttForwardGate()
	private(set) var isConnected = false
	private(set) var droppedNoPayload = 0

	init(radio: AdditionalRadio, proxy: MqttClientProxyManager = MqttClientProxyManager()) {
		self.radio = radio
		self.proxy = proxy
		proxy.delegate = self
	}

	private var radioName: String {
		radio.map { $0.session.device.shortName ?? $0.session.device.name } ?? "?"
	}

	/// Publishes a proxy message from the radio to the broker.
	func publish(_ message: MqttClientProxyMessage) {
		guard let brokerMessage = MqttProxyPackets.uplink(message) else {
			Logger.mqtt.warning("📲 [MQTT] [\(self.radioName, privacy: .public)] proxy message with no payload on \(message.topic, privacy: .public)")
			return
		}
		proxy.mqttClientProxy?.publish(brokerMessage)
	}

	func stop() {
		proxy.delegate = nil
		proxy.disconnect()
		isConnected = false
	}

	// MARK: MqttClientProxyManagerDelegate

	func onMqttConnected() {
		isConnected = true
		Logger.mqtt.info("📲 [MQTT] [\(self.radioName, privacy: .public)] connected; subscribing to \(self.proxy.topics.count, privacy: .public) topics")
		for topic in proxy.topics {
			proxy.mqttClientProxy?.subscribe(topic, qos: .qos1)
		}
	}

	func onMqttDisconnected() {
		isConnected = false
		Logger.mqtt.info("📲 [MQTT] [\(self.radioName, privacy: .public)] disconnected")
	}

	func onMqttError(message: String) {
		isConnected = false
		Logger.mqtt.error("📲 [MQTT] [\(self.radioName, privacy: .public)] \(message, privacy: .public)")
	}

	func onMqttMessageReceived(message: CocoaMQTTMessage) {
		guard let radio else { return }
		let myNodeNum = UInt32(truncatingIfNeeded: radio.session.nodeNum ?? 0)
		switch MqttProxyPackets.downlink(topic: message.topic, payload: Data(message.payload), retained: message.retained, myNodeNum: myNodeNum) {
		case .dropStat:
			return
		case .dropNoPayload:
			droppedNoPayload += 1
			return
		case .forward(let toRadio, _):
			let connection = radio.session.connection
			let gate = forwardGate
			Task {
				guard await gate.tryAcquire() else { return }
				defer { Task { await gate.release() } }
				try? await connection.send(toRadio)
			}
		}
	}
}

// MARK: - Starting and stopping (feature 021, T100)

extension AccessoryManager {

	/// Starts the radio's own MQTT client proxy when its config asks for one (MQTT enabled
	/// with "proxy to client"). Called once its config handshake is done.
	func startAdditionalMqtt(_ radio: AdditionalRadio) async {
		radio.mqtt?.stop()
		radio.mqtt = nil
		guard let radioNum = radio.session.nodeNum else { return }
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == radioNum })
		guard let node = try? context.fetch(descriptor).first,
			  let mqttConfig = node.mqttConfig, mqttConfig.enabled, mqttConfig.proxyToClientEnabled else {
			return
		}
		let bridge = AdditionalRadioMqttBridge(radio: radio)
		radio.mqtt = bridge
		Logger.mqtt.info("📲 [MQTT] Starting the client proxy for \(radio.session.device.name, privacy: .public)")
		// Same short delay as the focused radio's: CFNetwork callbacks firing before the app is
		// ready have crashed CocoaMQTT's stream parser at launch.
		try? await Task.sleep(for: .seconds(1))
		guard additionalRadios[radio.id] === radio, radio.mqtt === bridge else { return }
		bridge.proxy.connectFromConfigSettings(node: node)
	}

	func stopAdditionalMqtt(_ radio: AdditionalRadio) {
		radio.mqtt?.stop()
		radio.mqtt = nil
	}
}
