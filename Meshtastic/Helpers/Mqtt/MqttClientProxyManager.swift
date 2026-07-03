//
//  MQTTManager.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 7/31/23.
//

import Foundation
import CocoaMQTT
import OSLog
import Security

protocol MqttClientProxyManagerDelegate: AnyObject {
	func onMqttConnected()
	func onMqttDisconnected()
	func onMqttMessageReceived(message: CocoaMQTTMessage)
	func onMqttError(message: String)
}

class MqttClientProxyManager {
	// Singleton Instance
	static let shared = MqttClientProxyManager()
	private static let defaultKeepAliveInterval: Int32 = 60
	weak var delegate: MqttClientProxyManagerDelegate?
	var mqttClientProxy: CocoaMQTT?
	/// Per-channel subscription topics built in `connectFromConfigSettings`.
	/// Mirrors Android: one `prefix/2/e/<channelName>/+` per downlink-enabled channel,
	/// plus `prefix/2/e/PKI/+` which is always subscribed.
	var topics: [String] = []
	var debugLog = false

	func connectFromConfigSettings(node: NodeInfoEntity) {
		let originalAddress = node.mqttConfig?.address ?? "mqtt.meshtastic.org"
		let defaultServerAddress = "mqtt.meshtastic.org"
		var useSsl = node.mqttConfig?.tlsEnabled == true
		var defaultServerPort = useSsl ? 8883 : 1883
		var host = originalAddress
		if originalAddress.contains(":") {
			host = host.components(separatedBy: ":")[0]
			defaultServerPort = Int(originalAddress.components(separatedBy: ":")[1]) ?? (useSsl ? 8883 : 1883)
		}
		// Require TLS for the public Server
		if host.lowercased() == defaultServerAddress {
			useSsl = true
			defaultServerPort = 8883
		}
		let port = defaultServerPort
		let root = node.mqttConfig?.root?.count ?? 0 > 0 ? node.mqttConfig?.root : "msh"
		let prefix = root!

		Logger.mqtt.info("📲 [MQTT] connectFromConfigSettings host=\(host, privacy: .public) port=\(port, privacy: .public) ssl=\(useSsl, privacy: .public) prefix=\(prefix, privacy: .public)")

		// Build per-channel subscription topics (mirrors Android MQTTRepositoryImpl):
		// - one topic per downlink-enabled channel: prefix/2/e/<channelName>/+
		// - PKI channel is always subscribed regardless of downlink settings
		//
		// The primary channel (role == 1) has an empty name in the protobuf when using
		// the factory default configuration. In that case, the firmware derives the MQTT
		// channel name from the LoRa modem preset (e.g. "LongFast" for LONG_FAST).
		var newTopics: [String] = []
		let allChannels = node.myInfo?.channels ?? []
		Logger.mqtt.info("📲 [MQTT] Building topics from \(allChannels.count, privacy: .public) channel(s)")
		for channel in allChannels {
			let idx = channel.index
			let role = channel.role
			let nameRaw = channel.name ?? ""
			let downlink = channel.downlinkEnabled
			guard downlink else {
				Logger.mqtt.info("📲 [MQTT]   ch[\(idx, privacy: .public)] role=\(role, privacy: .public) name='\(nameRaw, privacy: .public)' — skip (downlink disabled)")
				continue
			}
			let channelName: String
			if !nameRaw.isEmpty {
				channelName = nameRaw
			} else if role == 1 {
				// Primary channel with empty name — use modem preset's MQTT name.
				channelName = mqttChannelName(forModemPreset: node.loRaConfig?.modemPreset ?? 0)
				Logger.mqtt.info("📲 [MQTT]   ch[\(idx, privacy: .public)] role=primary name='' → derived '\(channelName, privacy: .public)' from modem preset \(node.loRaConfig?.modemPreset ?? 0, privacy: .public)")
			} else {
				Logger.mqtt.info("📲 [MQTT]   ch[\(idx, privacy: .public)] role=\(role, privacy: .public) name='' — skip (no name, not primary)")
				continue
			}
			let topic = prefix + "/2/e/" + channelName + "/+"
			Logger.mqtt.info("📲 [MQTT]   ch[\(idx, privacy: .public)] → \(topic, privacy: .public)")
			newTopics.append(topic)
		}
		newTopics.append(prefix + "/2/e/PKI/+")
		topics = newTopics
		Logger.mqtt.info("📲 [MQTT] Final topic list (\(newTopics.count, privacy: .public)): \(newTopics.joined(separator: ", "), privacy: .public)")

		// Require opt in to map report terms to connect
		if node.mqttConfig?.mapReportingEnabled ?? false && UserDefaults.mapReportingOptIn || !(node.mqttConfig?.mapReportingEnabled ?? false) {
			connect(host: host, port: port, useSsl: useSsl, node: node)
		} else {
			delegate?.onMqttError(message: "MQTT Map Reporting Terms need to be accepted.")
		}
	}

	func connect(host: String, port: Int, useSsl: Bool, node: NodeInfoEntity) {
		guard !host.isEmpty else {
			delegate?.onMqttDisconnected()
			return
		}
		// UUID suffix prevents SESSION_TAKEN_OVER when multiple clients share the same node ID
		// (mirrors Android: "MeshtasticAndroidMqttProxy-<nodeId>-<uuid>")
		let clientId = "MeshtasticAppleMqttProxy-" + (node.user?.userId ?? String(ProcessInfo().processIdentifier)) + "-" + UUID().uuidString
		Logger.mqtt.info("📲 [MQTT] connect clientId=\(clientId, privacy: .public)")
		mqttClientProxy = CocoaMQTT(clientID: clientId, host: host, port: UInt16(port))
		if let mqttClient = mqttClientProxy {
			mqttClient.enableSSL = useSsl
			mqttClient.allowUntrustCACertificate = true
			mqttClient.username =  node.mqttConfig?.username
			mqttClient.password = node.mqttConfig?.password
			mqttClient.keepAlive = 60
			mqttClient.cleanSession = true
			if debugLog {
				mqttClient.logLevel = .debug
			}
			mqttClient.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
			mqttClient.autoReconnect = true
			mqttClient.delegate = self
			let success = mqttClient.connect()
			if !success {
				Logger.mqtt.error("📲 [MQTT] connect() returned false — broker unreachable?")
				delegate?.onMqttError(message: "Mqtt connect error")
			}
		} else {
			Logger.mqtt.error("📲 [MQTT] CocoaMQTT init failed")
			delegate?.onMqttError(message: "Mqtt initialization error")
		}
	}

	func subscribe(topic: String, qos: CocoaMQTTQoS) {
		Logger.mqtt.info("📲 [MQTT] subscribe topic=\(topic, privacy: .public) qos=\(qos.rawValue, privacy: .public)")
		mqttClientProxy?.subscribe(topic, qos: qos)
	}

	func unsubscribe(topic: String) {
		mqttClientProxy?.unsubscribe(topic)
		Logger.mqtt.info("📲 [MQTT] unsubscribe topic=\(topic, privacy: .public)")
	}

	func publish(message: String, topic: String, qos: CocoaMQTTQoS) {
		mqttClientProxy?.publish(topic, withString: message, qos: qos)
		Logger.mqtt.debug("📲 [MQTT] publish topic=\(topic, privacy: .public)")
	}

	func disconnect() {
		if let client = mqttClientProxy {
			client.disconnect()
			Logger.mqtt.info("📲 [MQTT] disconnect called")
		}
	}

	// Maps a LoRa modem preset raw value to the channel name the firmware uses when
	// publishing MQTT topics for an unnamed primary channel. Values match the firmware's
	// MeshService::channelName() function.
	private func mqttChannelName(forModemPreset preset: Int32) -> String {
		switch preset {
		case 0:  return "LongFast"
		case 1:  return "LongSlow"
		case 2:  return "VLongSlow"
		case 3:  return "MedSlow"
		case 4:  return "MedFast"
		case 5:  return "ShortSlow"
		case 6:  return "ShortFast"
		case 7:  return "LongMod"
		case 8:  return "ShortTurbo"
		case 9:  return "LongTurbo"
		case 10: return "LiteFast"
		case 11: return "LiteSlow"
		case 12: return "NarrowFast"
		case 13: return "NarrowSlow"
		default: return "LongFast"
		}
	}
}

extension MqttClientProxyManager: CocoaMQTTDelegate {
	func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
		Logger.mqtt.info("📲 [MQTT] didConnectAck: \(ack, privacy: .public)")
		if ack == .accept {
			delegate?.onMqttConnected()
		} else {
			var errorDescription = "Unknown Error"
			switch ack {
			case .accept:
				errorDescription = "No Error"
			case .unacceptableProtocolVersion:
				errorDescription = "Unacceptable Protocol version"
			case .identifierRejected:
				errorDescription = "Invalid Id"
			case .serverUnavailable:
				errorDescription = "Invalid Server"
			case .badUsernameOrPassword:
				errorDescription = "Invalid Credentials"
			case .notAuthorized:
				errorDescription = "Authorization Error"
			default:
				errorDescription = "Unknown Error"
			}
			Logger.mqtt.error("📲 [MQTT] broker rejected connection: \(errorDescription, privacy: .public)")
			delegate?.onMqttError(message: errorDescription)
			self.disconnect()
		}
	}

	func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
		let isValid = SecTrustEvaluateWithError(trust, nil)
		if isValid {
			Logger.mqtt.info("📲 [MQTT] TLS cert valid")
			completionHandler(true)
		} else {
			Logger.mqtt.warning("📲 [MQTT] TLS cert invalid — proceeding anyway (allowUntrustCACertificate=true)")
			completionHandler(true)
		}
	}

	func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
		if let err {
			Logger.mqtt.warning("📲 [MQTT] disconnected with error: \(err.localizedDescription, privacy: .public)")
			delegate?.onMqttError(message: err.localizedDescription)
		} else {
			Logger.mqtt.info("📲 [MQTT] disconnected cleanly")
		}
		delegate?.onMqttDisconnected()
	}

	func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
		Logger.mqtt.info("📲 [MQTT] published id=\(id, privacy: .public) topic=\(message.topic, privacy: .public) bytes=\(message.payload.count, privacy: .public)")
	}

	func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
		Logger.mqtt.debug("📲 [MQTT] publish ack id=\(id, privacy: .public)")
	}

	public func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
		Logger.mqtt.info("📲 [MQTT] received topic=\(message.topic, privacy: .public) bytes=\(message.payload.count, privacy: .public) retained=\(message.retained, privacy: .public)")
		delegate?.onMqttMessageReceived(message: message)
	}

	func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
		let successTopics = (success.allKeys as? [String] ?? []).sorted().joined(separator: ", ")
		if failed.isEmpty {
			Logger.mqtt.info("📲 [MQTT] subscribed OK (\(success.allKeys.count, privacy: .public)): \(successTopics, privacy: .public)")
		} else {
			Logger.mqtt.error("📲 [MQTT] subscribe: \(success.allKeys.count, privacy: .public) OK, \(failed.count, privacy: .public) FAILED: \(failed.joined(separator: ", "), privacy: .public)")
		}
	}

	func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
		Logger.mqtt.info("📲 [MQTT] unsubscribed: \(topics.joined(separator: ", "), privacy: .public)")
	}

	func mqttDidPing(_ mqtt: CocoaMQTT) {
		Logger.mqtt.debug("📲 [MQTT] ping")
	}

	func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
		Logger.mqtt.debug("📲 [MQTT] pong")
	}
}
