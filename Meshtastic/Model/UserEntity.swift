//
//  UserEntity.swift
//  Meshtastic
//
//  SwiftData model for user information.
//

import Foundation
import SwiftData

@Model
final class UserEntity {
	var hwDisplayName: String?
	var hwModel: String?
	var hwModelId: Int32 = 0
	var isLicensed: Bool = false
	var keyMatch: Bool = true
	var lastMessage: Date?
	var longName: String?
	var mute: Bool = false
	var newPublicKey: Data?
	var num: Int64 = 0
	var numString: String?
	var pkiEncrypted: Bool = false
	var publicKey: Data?
	var role: Int32 = 0
	var shortName: String?
	var unmessagable: Bool = false
	var userId: String?

	@Relationship(inverse: \MessageEntity.fromUser)
	var sentMessages: [MessageEntity] = []

	@Relationship(inverse: \MessageEntity.toUser)
	var receivedMessages: [MessageEntity] = []

	var userNode: NodeInfoEntity?

	init() {}
}
