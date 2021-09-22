//
//  MessageModel.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 9/21/21.
//
import Foundation

struct ChatMessage : Identifiable
{
    let id: UUID
    var messageId: UInt32
    var messageTimestamp: Int64
    var fromUserId: String
    var toUserId: String
    var fromUserLongName: String
    var toUserLongName: String
    var receivedACK: Bool
    var messagePayload: String
    var direction: String
    
    init(id: UUID = UUID(), messageId: UInt32, messageTimeStamp: Int64, fromUserId: String, toUserId: String, fromUserLongName: String, toUserLongName: String, receivedACK: Bool, messagePayload: String, direction: String)
    {
        self.id = id
        self.messageId = messageId
        self.messageTimestamp = messageTimeStamp
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.fromUserLongName = fromUserLongName
        self.toUserLongName = toUserLongName
        self.receivedACK = receivedACK
        self.messagePayload = messagePayload
        self.direction = direction
    }

}
