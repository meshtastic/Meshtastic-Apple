//
//  MessageModel.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 9/21/21.
//
import Foundation

struct MessageModel: Identifiable, Codable {
    let id: UUID
    var messageId: UInt32
    var messageTimestamp: UInt32
    var fromUserId: UInt32
    var toUserId: UInt32
    var fromUserLongName: String
    var toUserLongName: String
    var fromUserShortName: String
    var toUserShortName: String
    var receivedACK: Bool
    var messagePayload: String
    var direction: String

    init(id: UUID = UUID(), messageId: UInt32, messageTimeStamp: UInt32, fromUserId: UInt32, toUserId: UInt32, fromUserLongName: String, toUserLongName: String, fromUserShortName: String, toUserShortName: String, receivedACK: Bool, messagePayload: String, direction: String) {
        self.id = id
        self.messageId = messageId
        self.messageTimestamp = messageTimeStamp
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.fromUserLongName = fromUserLongName
        self.toUserLongName = toUserLongName
        self.fromUserShortName = fromUserShortName
        self.toUserShortName = toUserShortName
        self.receivedACK = receivedACK
        self.messagePayload = messagePayload
        self.direction = direction
    }

}

extension MessageModel {

    static var data: [MessageModel] {
        [
            // MessageModel(messageId: 3773493338, messageTimeStamp: 1632407404, fromUserId: 2930161432, toUserId: 4294967295, fromUserLongName: "TBEAM ARMY GREEN", toUserLongName: "Unknown 1", fromUserShortName: "GVH", toUserShortName: "U1", receivedACK: false, messagePayload: "yo", direction: "received")
        ]
    }
}

extension MessageModel {
    struct Data {
        var id: UUID
        var messageId: UInt32
        var messageTimestamp: UInt32
        var fromUserId: UInt32
        var toUserId: UInt32
        var fromUserLongName: String
        var toUserLongName: String
        var fromUserShortName: String
        var toUserShortName: String
        var receivedACK: Bool
        var messagePayload: String
        var direction: String

    }

    var data: Data {
        return Data(id: id, messageId: messageId, messageTimestamp: messageTimestamp, fromUserId: fromUserId, toUserId: toUserId, fromUserLongName: fromUserLongName, toUserLongName: toUserLongName, fromUserShortName: fromUserShortName, toUserShortName: toUserShortName, receivedACK: receivedACK, messagePayload: messagePayload, direction: direction)
    }

    mutating func update(from data: Data) {
        messageId = data.messageId
        messageTimestamp = data.messageTimestamp
        fromUserId = data.fromUserId
        toUserId = data.toUserId
        fromUserLongName = data.fromUserLongName
        toUserLongName = data.toUserLongName
        fromUserShortName = data.fromUserShortName
        toUserShortName = data.toUserShortName
        receivedACK = data.receivedACK
        messagePayload  = data.messagePayload
        direction = data.direction
    }
}
