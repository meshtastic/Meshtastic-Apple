import CocoaMQTT

protocol MQTTManagerDelegate: AnyObject {
	func onMqttConnected()
	func onMqttDisconnected()
	func onMqttMessageReceived(message: CocoaMQTTMessage)
	func onMqttError(message: String)
}
