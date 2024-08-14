import CoreData
import Foundation
import MeshtasticProtobufs

extension ChannelEntity {
	var allPrivateMessages: [MessageEntity]? {
		let context = Persistence.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [
			NSSortDescriptor(
				key: "messageTimestamp",
				ascending: true
			)
		]
		fetchRequest.predicate = NSPredicate(
			format: "channel == %ld AND toUser == nil",
			index
		)

		return try? context.fetch(fetchRequest)
	}

	var unreadMessages: Int {
		guard let allPrivateMessages else {
			return 0
		}

		return allPrivateMessages.filter { message in
			message.read == false
		}.count
	}

	var protoBuf: Channel {
		var channel = Channel()
		channel.index = index
		channel.settings.name = name ?? ""
		channel.settings.psk = psk ?? Data()
		channel.role = Channel.Role(rawValue: Int(role)) ?? Channel.Role.secondary
		channel.settings.moduleSettings.positionPrecision = UInt32(positionPrecision)

		return channel
	}
}
