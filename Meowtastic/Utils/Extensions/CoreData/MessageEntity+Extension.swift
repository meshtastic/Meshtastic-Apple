import Foundation

extension MessageEntity {
	var timestamp: Date {
		Date(timeIntervalSince1970: TimeInterval(messageTimestamp))
	}

	var canRetry: Bool {
		ackError == 9 || ackError == 5 || ackError == 3
	}
}
