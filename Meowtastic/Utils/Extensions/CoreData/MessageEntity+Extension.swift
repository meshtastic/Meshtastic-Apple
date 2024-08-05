import Foundation

extension MessageEntity {
	var timestamp: Date {
		let time = messageTimestamp <= 0 ? receivedTimestamp : messageTimestamp
		return Date(timeIntervalSince1970: TimeInterval(time))
	}

	var canRetry: Bool {
		ackError == 9 || ackError == 5 || ackError == 3
	}
}
