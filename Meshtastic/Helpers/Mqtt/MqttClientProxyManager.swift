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
	enum ConnectionStatus {
		case connecting
		case connected
		case disconnecting
		case disconnected
		case error
		case none
	}
	
	enum MqttQos: Int {
		case atMostOnce = 0
		case atLeastOnce = 1
		case exactlyOnce = 2
	}
	
	// Singleton Instance
	static let shared = MqttClientProxyManager()
	
	private static let defaultKeepAliveInterval: Int32 = 60

	weak var delegate: MqttClientProxyManagerDelegate?
	var status = ConnectionStatus.none
	
	var mqttClientProxy: CocoaMQTT?
	
	var topic = "msh/2/c"
	
	private init() {
		
	}
	
	func connectFromConfigSettings(node: NodeInfoEntity) {
		
		let defaultServerAddress = "mqtt.meshtastic.org"
		let defaultServerPort = 1883
		var host = node.mqttConfig?.address
		if host == nil || host!.isEmpty {
			host = defaultServerAddress
		}
		
		if let host = host {
			let port = defaultServerPort
			let username = node.mqttConfig?.username
			let password = node.mqttConfig?.password
			
			let root = node.mqttConfig?.root?.count ?? 0 > 0 ? node.mqttConfig?.root : "msh"
			let prefix = root! + "/2/c"
			topic = prefix + "/#"
			let qos = CocoaMQTTQoS(rawValue :UInt8(1))!
			connect(host: host, port: port, username: username, password: password, topic: topic, qos: qos, cleanSession: true)
		}
	}
	
	func connect(host: String, port: Int, username: String?, password: String?, topic: String?, qos: CocoaMQTTQoS, cleanSession: Bool) {
		
		guard !host.isEmpty else {
			delegate?.onMqttDisconnected()
			return
		}
		
		status = .connecting
		
		let clientId = "MeshtasticAppleMqttProxy-" + String(ProcessInfo().processIdentifier)
		
		mqttClientProxy = CocoaMQTT(clientID: clientId, host: host, port: UInt16(port))
		if let mqttClient = mqttClientProxy {
			
			mqttClient.username = username
			mqttClient.password = password
			mqttClient.keepAlive = 60
			mqttClient.cleanSession = cleanSession
#if DEBUG
			mqttClient.logLevel = .debug
#endif
			mqttClient.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
			mqttClient.autoReconnect = true
			mqttClient.delegate = self
			let success = mqttClient.connect()
			if !success {
				delegate?.onMqttError(message: "Mqtt connect error")
				status = .error
			}
		} else {
			delegate?.onMqttError(message: "Mqtt initialization error")
			status = .error
		}
	}
	
	func subscribe(topic: String, qos: MqttQos) {
		print("📲 MQTT Client Proxy subscribed to: " + topic)
		let qos = CocoaMQTTQoS(rawValue :UInt8(qos.rawValue))!
		mqttClientProxy?.subscribe(topic, qos: qos)
	}
	
	func unsubscribe(topic: String) {
		mqttClientProxy?.unsubscribe(topic)
		print("📲 MQTT Client Proxy unsubscribe for: " + topic)
	}
	
	func publish(message: String, topic: String, qos: MqttQos) {
		let qos = CocoaMQTTQoS(rawValue :UInt8(qos.rawValue))!
		mqttClientProxy?.publish(topic, withString: message, qos: qos)
		print("📲 MQTT Client Proxy publish for: " + topic)
	}
	
	func disconnect() {
		//MqttSettings.shared.isConnected = false
		
		if let client = mqttClientProxy {
			status = .disconnecting
			client.disconnect()
			print("📲 MQTT Client Proxy Disconnected")
		} else {
			status = .disconnected
		}
	}
}

extension MqttClientProxyManager: CocoaMQTTDelegate {
	
	func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
		
		print("📲 MQTT Client Proxy didConnectAck: \(ack)")
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
			print(errorDescription)
			delegate?.onMqttError(message: errorDescription)
			
			//self.disconnect()                       // Stop reconnecting
			//mqttSettings.isConnected = false        // Disable automatic connect on start
		}
		
		self.status = ack == .accept ? ConnectionStatus.connected : ConnectionStatus.error      // Set AFTER sending onMqttError (so the delegate can detect that was an error while establishing connection)
	}
	
	func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
		print("mqttDidDisconnect: \(err?.localizedDescription ?? "")")

		if let error = err, status == .connecting {
			delegate?.onMqttError(message: error.localizedDescription)
		}

		status = err == nil ? .disconnected : .error
		delegate?.onMqttDisconnected()
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
		print("📲 MQTT Client Proxy didPublishMessage from MqttClientProxyManager: \(message)")
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
		print("📲 MQTT Client Proxy didPublishAck from MqttClientProxyManager: \(id)")
	}

	public func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
		delegate?.onMqttMessageReceived(message: message)
		print("📲 MQTT Client Proxy message received on topic: \(message.topic)")
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
		print("didSubscribeTopics: \(success.allKeys.count) topics. failed: \(failed.count) topics")
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
		print("didUnsubscribeTopics: \(topics.joined(separator: ", "))")
	}
	
	func mqttDidPing(_ mqtt: CocoaMQTT) {
		//print("mqttDidPing")
	}
	
	func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
		//print("mqttDidReceivePong")
	}
}
