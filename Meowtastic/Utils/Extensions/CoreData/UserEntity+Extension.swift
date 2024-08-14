import CoreData
import Foundation
import MeshtasticProtobufs

extension UserEntity {
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
			format: "(toUser == %@ OR fromUser == %@) AND toUser != nil AND fromUser != nil AND admin = false AND portNum != 10", self, self
		)

		return try? context.fetch(fetchRequest)
	}

	var sensorMessageList: [MessageEntity]? {
		let context = Persistence.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: true)]
		fetchRequest.predicate = NSPredicate(format: "(fromUser == %@) AND portNum = 10", self)

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
}

public func createUser(num: Int64, context: NSManagedObjectContext) -> UserEntity {
	let newUser = UserEntity(context: context)
	newUser.num = Int64(num)

	let userId = String(format: "%2X", num)
	newUser.userId = "!\(userId)"

	let last4 = String(userId.suffix(4))
	newUser.longName = "Meshtastic \(last4)"
	newUser.shortName = last4
	newUser.hwModel = "UNSET"

	return newUser
}
