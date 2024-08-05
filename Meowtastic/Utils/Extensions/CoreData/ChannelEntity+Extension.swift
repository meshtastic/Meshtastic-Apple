import CoreData
import Foundation
import MeshtasticProtobufs

extension ChannelEntity {
	var allPrivateMessages: [MessageEntity]? {
		self.value(forKey: "allPrivateMessages") as? [MessageEntity]
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
		channel.index = self.index
		channel.settings.name = self.name ?? ""
		channel.settings.psk = self.psk ?? Data()
		channel.role = Channel.Role(rawValue: Int(self.role)) ?? Channel.Role.secondary
		channel.settings.moduleSettings.positionPrecision = UInt32(self.positionPrecision)

		return channel
	}
}
