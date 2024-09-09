import CocoaMQTT
import Foundation
import OSLog

final class MQTTManager {
	var topic: String?
	var client: CocoaMQTT?
	var delegate: MQTTManagerDelegate?

	func connect(config: MQTTConfigEntity) {
		guard config.enabled else {
			Logger.mqtt.info("MQTT proxy is disabled, not connecting to MQTT broker")
			return
		}

		let host: String
		let useSsl = config.tlsEnabled == true
		var port = useSsl ? 8883 : 1883

		if let address = config.address, !address.isEmpty {
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
		if let root = config.root, !root.isEmpty {
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
			username: config.username,
			password: config.password,
			topic: topic
		)
	}

	// swiftlint:disable:next function_parameter_count
	private func connect(
		host: String,
		port: Int,
		useSsl: Bool,
		username: String?,
		password: String?,
		topic: String?
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
		client.username = username
		client.password = password
		client.enableSSL = useSsl
		client.allowUntrustCACertificate = true
		client.autoReconnect = true
		client.cleanSession = false // allow delivering old messages
		client.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
		#if DEBUG
		client.logLevel = .debug
		#endif

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
		client = nil
	}
}
