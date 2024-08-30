import CocoaMQTT
import Foundation
import OSLog

class MQTTManager {
	var topic: String?
	var client: CocoaMQTT?

	weak var delegate: MQTTManagerDelegate?

	private var debugLog = false

	func connectFromConfigSettings(node: NodeInfoEntity) {
		let host: String
		let useSsl = node.mqttConfig?.tlsEnabled == true
		var port = useSsl ? 8883 : 1883

		if let address = node.mqttConfig?.address, !address.isEmpty {
			if address.contains(":") {
				host = address.components(separatedBy: ":")[0]
				port = Int(address.components(separatedBy: ":")[1]) ?? (useSsl ? 8883 : 1883)
			}
			else {
				host = address
			}
		}
		else {
			host = "mqtt.meshtastic.org"
		}

		let minimumVersion = "2.3.2"
		let isSupportedVersion = [.orderedAscending, .orderedSame]
			.contains(minimumVersion.compare(UserDefaults.firmwareVersion, options: .numeric))

		let rootTopic: String
		if let root = node.mqttConfig?.root, !root.isEmpty {
			rootTopic = root
		}
		else {
			rootTopic = "msh"
		}
		topic = rootTopic + (isSupportedVersion ? "/2/e" : "/2/c") + "/#"

		connect(
			host: host,
			port: port,
			useSsl: useSsl,
			username: node.mqttConfig?.username,
			password: node.mqttConfig?.password,
			topic: topic,
			cleanSession: true
		)
	}

	// swiftlint:disable:next function_parameter_count
	func connect(
		host: String,
		port: Int,
		useSsl: Bool,
		username: String?,
		password: String?,
		topic: String?,
		cleanSession: Bool
	) {
		guard !host.isEmpty else {
			delegate?.onMqttDisconnected()

			return
		}

		let client = CocoaMQTT(
			clientID: "MeowtasticMQTT_" + String(ProcessInfo().processIdentifier),
			host: host,
			port: UInt16(port)
		)

		client.delegate = self
		client.enableSSL = useSsl
		client.allowUntrustCACertificate = true
		client.username = username
		client.password = password
		client.keepAlive = 60
		client.cleanSession = cleanSession
		client.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
		client.autoReconnect = true
		if debugLog {
			client.logLevel = .debug
		}

		if !client.connect() {
			delegate?.onMqttError(message: "Mqtt connect error")
		}

		self.client = client
	}

	func subscribe(topic: String, qos: CocoaMQTTQoS) {
		client?.subscribe(topic, qos: qos)
	}

	func unsubscribe(topic: String) {
		client?.unsubscribe(topic)
	}

	func publish(message: String, topic: String, qos: CocoaMQTTQoS) {
		client?.publish(topic, withString: message, qos: qos)
	}

	func disconnect() {
		client?.disconnect()
	}
}
