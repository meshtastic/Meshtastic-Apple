import CocoaMQTT
import CoreBluetooth
import FirebaseAnalytics
import MeshtasticProtobufs
import OSLog

extension BLEManager: MqttClientProxyManagerDelegate {
	func onMqttConnected() {
		mqttError = ""
		mqttProxyConnected = true
		mqttManager.mqttClientProxy?.subscribe(mqttManager.topic)

		Analytics.logEvent(AnalyticEvents.mqttConnect.id, parameters: nil)
	}

	func onMqttDisconnected() {
		mqttProxyConnected = false

		Analytics.logEvent(AnalyticEvents.mqttDisconnect.id, parameters: nil)
	}

	func onMqttMessageReceived(message: CocoaMQTTMessage) {
		guard !message.topic.contains("/stat/") else {
			return
		}

		var proxyMessage = MqttClientProxyMessage()
		proxyMessage.topic = message.topic
		proxyMessage.data = Data(message.payload)
		proxyMessage.retained = message.retained

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.mqttClientProxyMessage = proxyMessage

		if
			let connectedDevice = getConnectedDevice(),
			let binaryData: Data = try? toRadio.serializedData()
		{
			connectedDevice.peripheral.writeValue(
				binaryData,
				for: characteristicToRadio,
				type: .withResponse
			)

			Analytics.logEvent(
				AnalyticEvents.mqttMessage.id,
				parameters: [
					"topic": message.topic
				]
			)
		}
	}

	func onMqttError(message: String) {
		mqttProxyConnected = false
		mqttError = message

		Analytics.logEvent(
			AnalyticEvents.mqttError.id,
			parameters: [
				"error": message
			]
		)
	}
}
