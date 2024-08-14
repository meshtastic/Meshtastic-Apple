import Foundation

extension MyInfoEntity {
	var messageList: [MessageEntity]? {
		let context = Persistence.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [
			NSSortDescriptor(
				key: "messageTimestamp",
				ascending: true
			)
		]
		fetchRequest.predicate = NSPredicate(
			format: "toUser == nil"
		)

		return try? context.fetch(fetchRequest)
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
