import CocoaMQTT
import Foundation

extension MQTTManager: CocoaMQTTDelegate {
	func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
		if ack == .accept {
			delegate?.onMqttConnected()
		}
		else {
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

			delegate?.onMqttError(message: errorDescription)

			disconnect()
		}
	}

	func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
		if let error = err {
			delegate?.onMqttError(message: error.localizedDescription)
		}
		delegate?.onMqttDisconnected()
	}

	public func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
		delegate?.onMqttMessageReceived(message: message)
	}

	func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
		// no-op
	}

	func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
		// no-op
	}

	func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
		// no-op
	}

	func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
		// no-op
	}

	func mqttDidPing(_ mqtt: CocoaMQTT) {
		// no-op
	}

	func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
		// no-op
	}
}
