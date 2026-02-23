//
//  ChatAdapters.swift
//  Meshtastic
//
//  Adapters to convert between Meshtastic Core Data entities and ExyteChat library types
//

import Foundation
import CoreData
import ExyteChat

extension UserEntity {
    
    func toChatUser(currentUserNum: Int64) -> User {
        let isCurrentUser = self.num == currentUserNum
        return User(
            id: String(self.num),
            name: self.longName ?? self.shortName ?? "Unknown",
            avatarURL: nil,
            isCurrentUser: isCurrentUser
        )
    }
}

extension MessageEntity {
    
    func toChatMessage(
        currentUserNum: Int64,
        allMessages: [MessageEntity] = [],
        preferredPeripheralNum: Int = -1
    ) -> Message {
        let messageId = String(self.messageId)
        let fromUserEntity = self.fromUser
        
        let isCurrentUser: Bool
        if let fromUser = fromUserEntity {
            isCurrentUser = fromUser.num == currentUserNum
        } else {
            isCurrentUser = false
        }
        
        let user: User
        if let fromUser = fromUserEntity {
            user = fromUser.toChatUser(currentUserNum: currentUserNum)
        } else {
            user = User(
                id: "unknown",
                name: "Unknown",
                avatarURL: nil,
                isCurrentUser: isCurrentUser
            )
        }
        
        var replyMessage: Message? = nil
        if self.replyID > 0, let replyEntity = allMessages.first(where: { $0.messageId == self.replyID }) {
            replyMessage = replyEntity.toChatMessage(
                currentUserNum: currentUserNum,
                allMessages: [],
                preferredPeripheralNum: preferredPeripheralNum
            )
        }
        
        return Message(
            id: messageId,
            user: user,
            text: self.messagePayload ?? "",
            attachments: [],
            createdAt: self.timestamp,
            replyMessage: replyMessage,
            status: self.determineMessageStatus(preferredPeripheralNum: Int64(preferredPeripheralNum))
        )
    }
    
    private func determineMessageStatus(preferredPeripheralNum: Int64) -> MessageStatus {
        guard Int64(preferredPeripheralNum) == fromUser?.num else {
            return .read
        }
        
        if receivedACK {
            return .read
        } else if ackError > 0 {
            return .error
        } else {
            return .sending
        }
    }
}

struct ChatMessageAdapter {
    
    static func convertMessages(
        from entities: [MessageEntity],
        currentUserNum: Int64,
        preferredPeripheralNum: Int = -1
    ) -> [Message] {
        return entities.map { entity in
            entity.toChatMessage(
                currentUserNum: currentUserNum,
                allMessages: entities,
                preferredPeripheralNum: preferredPeripheralNum
            )
        }
    }
}
