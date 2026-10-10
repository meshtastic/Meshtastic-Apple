//
//  AccessoryManager+RadioMQTT.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import CocoaMQTT
import Foundation
import MeshtasticProtobufs
import OSLog
@preconcurrency import SwiftData

/// One radio's MQTT client proxy (feature 021, T100, T071c).
///
/// A radio with MQTT "proxy to client" on has no internet of its own and relies on the phone to
/// reach the broker. Every connected radio gets its own proxy instance, broker client and forward
/// gate, built from its own MQTT config and channels, so its uplink and downlink never mix with
/// another radio's. The MQTT icon and the MQTT settings show the radio they're about.
///
/// `@preconcurrency`: CocoaMQTT calls its delegate on the main queue (its default
/// `delegateQueue`, never overridden), which the runtime isolation check confirms.
@MainActor
final class RadioMqttClient: @preconcurrency MqttClientProxyManagerDelegate {
	let proxy: MqttClientProxyManager
	private weak var radio: RadioSession?
	/// One broker-to-radio write at a time; extra packets are dropped rather than queued, so
	/// global broker traffic can't build a backlog the radio can't drain.
	private let forwardGate = MqttForwardGate()
	private(set) var isConnected = false
	/// The broker's last error, for the MQTT settings. Cleared when it connects.
	private(set) var errorMessage = ""
	private(set) var droppedNoPayload = 0
	/// Called when `isConnected` or `errorMessage` changes, so the views showing them redraw.
	var onStateChange: (() -> Void)?

	init(radio: RadioSession, proxy: MqttClientProxyManager = MqttClientProxyManager()) {
		self.radio = radio
		self.proxy = proxy
		proxy.delegate = self
	}

	private var radioName: String {
		radio.map { $0.device.shortName ?? $0.device.name } ?? "?"
	}

	/// The broker topics it subscribes to, one per downlink-enabled channel plus PKI.
	var topics: [String] { proxy.topics }

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
		onStateChange?()
	}

	// MARK: MqttClientProxyManagerDelegate

	func onMqttConnected() {
		isConnected = true
		errorMessage = ""
		onStateChange?()
		Logger.mqtt.info("📲 [MQTT] [\(self.radioName, privacy: .public)] connected; subscribing to \(self.proxy.topics.count, privacy: .public) topics")
		for topic in proxy.topics {
			proxy.mqttClientProxy?.subscribe(topic, qos: .qos1)
		}
	}

	func onMqttDisconnected() {
		isConnected = false
		onStateChange?()
		Logger.mqtt.info("📲 [MQTT] [\(self.radioName, privacy: .public)] disconnected")
	}

	func onMqttError(message: String) {
		isConnected = false
		errorMessage = message
		onStateChange?()
		Logger.mqtt.error("📲 [MQTT] [\(self.radioName, privacy: .public)] \(message, privacy: .public)")
	}

	func onMqttMessageReceived(message: CocoaMQTTMessage) {
		guard let radio else { return }
		// Drops provably-undeliverable packets before spending any radio bandwidth on them, and
		// clamps the hop limit to 0 (`MqttProxyPackets.downlink`).
		let myNodeNum = UInt32(truncatingIfNeeded: radio.nodeNum ?? 0)
		switch MqttProxyPackets.downlink(topic: message.topic, payload: Data(message.payload), retained: message.retained, myNodeNum: myNodeNum) {
		case .dropStat:
			return
		case .dropNoPayload:
			droppedNoPayload += 1
			Logger.mqtt.debug("📲 [MQTT] [\(self.radioName, privacy: .public)] drop (no payload) topic=\(message.topic, privacy: .public) count=\(self.droppedNoPayload, privacy: .public)")
			return
		case .forward(let toRadio, _):
			let connection = radio.connection
			let gate = forwardGate
			Task {
				guard await gate.tryAcquire() else {
					Logger.mqtt.debug("📲 [MQTT] drop (write in flight): \(message.topic, privacy: .public)")
					return
				}
				defer { Task { await gate.release() } }
				try? await connection.send(toRadio)
			}
		}
	}
}

// MARK: - Starting and stopping (feature 021, T100, T071c)

extension AccessoryManager {

	/// Reads the settings of `radio`'s modules that change how its packets are handled (range
	/// test), from its own config. Connect Step 8, and after it reboots.
	func applyModuleSettings(_ radio: RadioSession) {
		guard let radioNum = radio.nodeNum else { return }
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == radioNum })
		guard let node = try? context.fetch(descriptor).first else { return }
		radio.wantRangeTestPackets = node.rangeTestConfig?.enabled ?? false
	}

	/// Starts the radio's own MQTT client proxy when its config asks for one (MQTT enabled
	/// with "proxy to client"), replacing one it already has. Connect Step 8, after it reboots,
	/// after its channels change, and from its MQTT settings.
	func startMqtt(_ radio: RadioSession) async {
		stopMqtt(radio)
		guard let radioNum = radio.nodeNum else { return }
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == radioNum })
		guard let node = try? context.fetch(descriptor).first,
			  let mqttConfig = node.mqttConfig, mqttConfig.enabled, mqttConfig.proxyToClientEnabled else {
			return
		}
		let client = RadioMqttClient(radio: radio)
		client.onStateChange = { [weak self] in self?.objectWillChange.send() }
		radio.mqtt = client
		Logger.mqtt.info("📲 [MQTT] Starting the client proxy for \(radio.device.name, privacy: .public)")
		// Brief delay so CFNetwork callbacks don't fire before the app is fully initialised —
		// prevents a launch-time SIGABRT in CocoaMQTT's stream parser.
		try? await Task.sleep(for: .seconds(1))
		guard isConnectedSession(radio), radio.mqtt === client else { return }
		client.proxy.connectFromConfigSettings(node: node)
	}

	func stopMqtt(_ radio: RadioSession) {
		radio.mqtt?.stop()
		radio.mqtt = nil
	}

	/// `startMqtt` / `stopMqtt` for the connected radio with node number `radioNum`: the MQTT
	/// settings and the channel editor, for the radio they configure.
	func startMqtt(forRadio radioNum: Int64) async {
		guard let session = connectedSession(forRadio: radioNum) else { return }
		await startMqtt(session)
	}

	func stopMqtt(forRadio radioNum: Int64) {
		guard let session = connectedSession(forRadio: radioNum) else { return }
		stopMqtt(session)
	}

	/// The MQTT client proxy of the connected radio with node number `radioNum`.
	func mqttClient(forRadio radioNum: Int64?) -> RadioMqttClient? {
		connectedSession(forRadio: radioNum)?.mqtt
	}

	/// True while `session` is the first radio or one of the radios connected alongside it.
	func isConnectedSession(_ session: RadioSession) -> Bool {
		session === activeConnection || additionalRadio(for: session) != nil
	}
}
