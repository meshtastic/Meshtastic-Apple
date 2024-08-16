import CocoaMQTT
import CoreBluetooth
import MeshtasticProtobufs
import OSLog

extension BLEManager: MqttClientProxyManagerDelegate {
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
		guard let binaryData: Data = try? toRadio.serializedData() else {
			return
		}
		if connectedPeripheral?.peripheral.state ?? .disconnected == .connected {
			connectedPeripheral.peripheral.writeValue(binaryData, for: characteristicToRadio, type: .withResponse)
		}
	}
	
	func onMqttError(message: String) {
		mqttProxyConnected = false
		mqttError = message
		Logger.services.info("📲 [MQTT Client Proxy] onMqttError: \(message, privacy: .public)")
	}
}