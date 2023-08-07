//
//  MQTTManager.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 7/31/23.
//

import Foundation
import CocoaMQTT

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
	
	static let shared = MqttClientProxyManager()
	private static let defaultKeepAliveInterval: Int32 = 60
	weak var delegate: CocoaMQTTDelegate?
	var status = ConnectionStatus.none
	var mqttClient: CocoaMQTT?
	
	private init() {
		
	}
	
	func connectFromConfigSettings(config: MQTTConfigEntity, metadata: DeviceMetadataEntity) {
		
		let defaultServerAddress = "mqtt.meshtastic.org"
		let defaultServerPort = 1883
		//let
		var host = config.address
		if host == nil || host!.isEmpty {
			host = defaultServerAddress
		}
		
		if let host = host {
			let port = defaultServerPort
			let username = config.username
			let password = config.password
			
			var root = config.root?.count ?? 0 > 0 ? config.root : "msh"
			var prefix = root! + "/2" //+ metadata.firmwareVersion!
			var topic = prefix + "/#"
			let qos = CocoaMQTTQoS(rawValue :UInt8(2))!
			connect(host: host, port: port, username: username, password: password, topic: topic, qos: qos, cleanSession: true)
		}
	}
	
	func connect(host: String, port: Int, username: String?, password: String?, topic: String?, qos: CocoaMQTTQoS, cleanSession: Bool) {
		
		let clientId = "MeshtasticAppleMqttProxy-" + String(ProcessInfo().processIdentifier)
		status = .connecting
		mqttClient = CocoaMQTT(clientID: clientId, host: host, port: UInt16(port))
		
		if let mqttClient = mqttClient {
			
			mqttClient.username = username
			mqttClient.password = password
			mqttClient.keepAlive = 60
			mqttClient.cleanSession = cleanSession
			mqttClient.logLevel = .debug
			mqttClient.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
			mqttClient.autoReconnect = true
			mqttClient.delegate = self
			let success = mqttClient.connect()
			if !success {
				status = .error
			} else {
				//mqttClient.subscribe(topic!, qos: qos)
				subscribe(topic: topic!, qos: MqttQos.atLeastOnce)
			}
		} else {
			status = .error
		}
	}
	
	func subscribe(topic: String, qos: MqttQos) {
		let qos = CocoaMQTTQoS(rawValue :UInt8(qos.rawValue))!
		mqttClient?.subscribe(topic, qos: qos)
		print("MQTT Client Proxy subscribed to: " + topic)
	}
	
	func unsubscribe(topic: String) {
		mqttClient?.unsubscribe(topic)
	}
	
	func publish(message: String, topic: String, qos: MqttQos) {
		let qos = CocoaMQTTQoS(rawValue :UInt8(qos.rawValue))!
		mqttClient?.publish(topic, withString: message, qos: qos)
	}
	
	func disconnect() {
		//MqttSettings.shared.isConnected = false
		
		if let client = mqttClient {
			status = .disconnecting
			client.disconnect()
		} else {
			status = .disconnected
		}
	}
}

extension MqttClientProxyManager: CocoaMQTTDelegate {
	
	func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
		completionHandler(true)
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
		
		print("didConnectAck: \(ack)")
		if ack == .accept {
			//delegate?.onMqttConnected()
			
			//			if let topic = mqttSettings.subscribeTopic, mqttSettings.isSubscribeEnabled {
			//				self.subscribe(topic: topic, qos: mqttSettings.subscribeQos)
			//			}
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
			//delegate?.onMqttError(message: errorDescription)
			
			//self.disconnect()                       // Stop reconnecting
			//mqttSettings.isConnected = false        // Disable automatic connect on start
		}
		
		self.status = ack == .accept ? ConnectionStatus.connected : ConnectionStatus.error      // Set AFTER sending onMqttError (so the delegate can detect that was an error while stablishing connection)
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
		print("didPublishMessage")
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
		print("didPublishAck")
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
		if let string = message.string {
			print("didReceiveMessage: \(string) from topic: \(message.topic)")
		} else {
			print("didReceiveMessage but message is not defined")
		}
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
		print("didSubscribeTopics: \(success.allKeys.count) topics. failed: \(failed.count) topics")
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
		print("didUnsubscribeTopics: \(topics.joined(separator: ", "))")
	}
	
	func mqttDidPing(_ mqtt: CocoaMQTT) {
		print("mqttDidPing")
	}
	
	func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
		print("mqttDidReceivePong")
	}
	
	func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
		print("mqttDidDisconnect")
	}
}
