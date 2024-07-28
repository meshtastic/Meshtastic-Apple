import Foundation

extension MyInfoEntity {
	var messageList: [MessageEntity]? {
		self.value(forKey: "allMessages") as? [MessageEntity]
	}

	var unreadMessages: Int {
		guard let messageList else {
			return 0
		}

		return messageList.filter { message in
			message.read == false
		}.count
	}

	var hasAdmin: Bool {
		guard let channels else {
			return false
		}
		
		return channels.filter { channel in
			(channel as AnyObject).name?.lowercased() == "admin"
		}.count > 0
	}
}
