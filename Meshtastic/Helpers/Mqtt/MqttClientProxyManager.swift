//
//  MQTTManager.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 7/31/23.
//

import Foundation
import CocoaMQTT

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
	var topic = "msh"
	var debugLog = false
	func connectFromConfigSettings(node: NodeInfoEntity) {
		let defaultServerAddress = "mqtt.meshtastic.org"
		let useSsl = node.mqttConfig?.tlsEnabled == true
		var defaultServerPort = useSsl ? 8883 : 1883
		var host = node.mqttConfig?.address
		if host == nil || host!.isEmpty {
			host = defaultServerAddress
		} else if host != nil && host!.contains(":") {
			if let fullHost = host {
				host = fullHost.components(separatedBy: ":")[0]
				defaultServerPort = Int(fullHost.components(separatedBy: ":")[1]) ?? (useSsl ? 8883 : 1883)
			}
		}
		let minimumVersion = "2.3.2"
		let currentVersion = UserDefaults.firmwareVersion
		let supportedVersion = minimumVersion.compare(currentVersion, options: .numeric) == .orderedAscending  || minimumVersion.compare(currentVersion, options: .numeric) == .orderedSame

		if let host = host {
			let port = defaultServerPort
			let username = node.mqttConfig?.username
			let password = node.mqttConfig?.password
			let root = node.mqttConfig?.root?.count ?? 0 > 0 ? node.mqttConfig?.root : "msh"
			let prefix = root!
			topic = prefix + (supportedVersion ? "/2/e" : "/2/c") + "/#"
			let qos = CocoaMQTTQoS(rawValue: UInt8(1))!
			connect(host: host, port: port, useSsl: useSsl, username: username, password: password, topic: topic, qos: qos, cleanSession: true)
		}
	}
	func connect(host: String, port: Int, useSsl: Bool, username: String?, password: String?, topic: String?, qos: CocoaMQTTQoS, cleanSession: Bool) {
		guard !host.isEmpty else {
			delegate?.onMqttDisconnected()
			return
		}
		let clientId = "MeshtasticAppleMqttProxy-" + String(ProcessInfo().processIdentifier)
		mqttClientProxy = CocoaMQTT(clientID: clientId, host: host, port: UInt16(port))
		if let mqttClient = mqttClientProxy {
			mqttClient.enableSSL = useSsl
			mqttClient.allowUntrustCACertificate = true
			mqttClient.username = username
			mqttClient.password = password
			mqttClient.keepAlive = 60
			mqttClient.cleanSession = cleanSession
			if debugLog {
				mqttClient.logLevel = .debug
			}
			mqttClient.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
			mqttClient.autoReconnect = true
			mqttClient.delegate = self
			let success = mqttClient.connect()
			if !success {
				delegate?.onMqttError(message: "Mqtt connect error")
			}
		} else {
			delegate?.onMqttError(message: "Mqtt initialization error")
		}
	}
	func subscribe(topic: String, qos: CocoaMQTTQoS) {
		logger.info("📲 MQTT Client Proxy subscribed to: \(topic)")
		mqttClientProxy?.subscribe(topic, qos: qos)
	}
	func unsubscribe(topic: String) {
		mqttClientProxy?.unsubscribe(topic)
		logger.info("📲 MQTT Client Proxy unsubscribe for: \(topic)")
	}
	func publish(message: String, topic: String, qos: CocoaMQTTQoS) {
		mqttClientProxy?.publish(topic, withString: message, qos: qos)
		logger.debug("📲 MQTT Client Proxy publish for: \(topic)")
	}
	func disconnect() {
		if let client = mqttClientProxy {
			client.disconnect()
			logger.info("📲 MQTT Client Proxy Disconnected")
		}
	}
}

extension MqttClientProxyManager: CocoaMQTTDelegate {
	func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
		logger.info("📲 MQTT Client Proxy didConnectAck: \(ack)")
		if ack == .accept {
			delegate?.onMqttConnected()
		} else {
			// Connection error
			var errorDescription = "Unknown Error"
			switch ack {
			case .accept:
				errorDescription = "No Error"
			case .unacceptableProtocolVersion:
				errorDescription = "Proto ver"
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
			logger.error("\(errorDescription)")
			delegate?.onMqttError(message: errorDescription)
			self.disconnect()
		}
	}
	func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
		logger.debug("mqttDidDisconnect: \(err?.localizedDescription ?? "")")

		if let error = err {
			delegate?.onMqttError(message: error.localizedDescription)
		}
		delegate?.onMqttDisconnected()
	}
	func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
		logger.debug("📲 MQTT Client Proxy didPublishMessage from MqttClientProxyManager: \(message)")
	}
	func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
		logger.debug("📲 MQTT Client Proxy didPublishAck from MqttClientProxyManager: \(id)")
	}

	public func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
		delegate?.onMqttMessageReceived(message: message)
		logger.debug("📲 MQTT Client Proxy message received on topic: \(message.topic)")
	}
	func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
		logger.info("📲 MQTT Client Proxy didSubscribeTopics: \(success.allKeys.count) topics. failed: \(failed.count) topics")
	}
	func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
		logger.info("didUnsubscribeTopics: \(topics.joined(separator: ", "))")
	}
	func mqttDidPing(_ mqtt: CocoaMQTT) {
		logger.info("📲 MQTT Client Proxy mqttDidPing")
	}
	func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
		logger.info("📲 MQTT Client Proxy mqttDidReceivePong")
	}
}
