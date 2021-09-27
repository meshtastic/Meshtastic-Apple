//
//  MessageModel.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 9/21/21.
//
import Foundation

struct MessageModel : Identifiable, Codable
{
    let id: UUID
    var messageId: UInt32
    var messageTimestamp: Int64
    var fromUserId: UInt32
    var toUserId: UInt32
    var fromUserLongName: String
    var toUserLongName: String
    var fromUserShortName: String
    var toUserShortName: String
    var receivedACK: Bool
    var messagePayload: String
    var direction: String
    
    init(id: UUID = UUID(), messageId: UInt32, messageTimeStamp: Int64, fromUserId: UInt32, toUserId: UInt32, fromUserLongName: String, toUserLongName: String, fromUserShortName: String, toUserShortName: String, receivedACK: Bool, messagePayload: String, direction: String)
    {
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
            // Put dev test data here
            MessageModel(messageId: 3773493287, messageTimeStamp: 1632407404, fromUserId: 4064715620, toUserId: 4294967295, fromUserLongName: "TLORA V1 #1", toUserLongName: "Unknown 1", fromUserShortName: "T#", toUserShortName: "U1", receivedACK: false, messagePayload: "I sent a super great message with amazing text", direction: "received"),
            MessageModel(messageId: 3773493338, messageTimeStamp: 1632643652, fromUserId: 2930161432, toUserId: 4294967295, fromUserLongName: "TBEAM ARMY GREEN", toUserLongName: "Unknown 1", fromUserShortName: "T#", toUserShortName: "U1", receivedACK: false, messagePayload: "It was the best message", direction: "received"),
            MessageModel(messageId: 3773493338, messageTimeStamp: 1632643652, fromUserId: 2930161432, toUserId: 4294967295, fromUserLongName: "TBEAM ARMY GREEN", toUserLongName: "Unknown 1", fromUserShortName: "TAG", toUserShortName: "U1", receivedACK: false, messagePayload: "SwiftUI is great, but it has been lacking of specific native controls, even though that gets much better year by year. One of them was the text view. When SwiftUI was first released, it had no native ", direction: "received"),
            MessageModel(messageId: 3773493338, messageTimeStamp: 1632643652, fromUserId: 2930161432, toUserId: 4294967295, fromUserLongName: "TBEAM ARMY GREEN", toUserLongName: "Unknown 1", fromUserShortName: "TAG", toUserShortName: "U1", receivedACK: false, messagePayload: "One of them was the text view. When SwiftUI was first released, it had no native equivalent of the text view; implementing a custom UIViewRepresentable type to contain UITextView was the only way to g", direction: "received"),
            MessageModel(messageId: 3773493338, messageTimeStamp: 1632407404, fromUserId: 2930161432, toUserId: 4294967295, fromUserLongName: "TBEAM ARMY GREEN", toUserLongName: "Unknown 1", fromUserShortName: "TAG", toUserShortName: "U1", receivedACK: false, messagePayload: "One of them was the text view. When SwiftUI was first released, it had no native equivalent of the text view; implementing a custom UIViewRepresentable type to contain UITextView was the only way to g", direction: "received"),
                       
            MessageModel(messageId: 3773493338, messageTimeStamp: 1632643652, fromUserId: 2930161432, toUserId: 4294967295, fromUserLongName: "TBEAM ARMY GREEN", toUserLongName: "Unknown 1", fromUserShortName: "GVH", toUserShortName: "U1", receivedACK: false, messagePayload: "yo", direction: "received"),
            
            MessageModel(messageId: 3773493338, messageTimeStamp: 1632407404, fromUserId: 2930161432, toUserId: 4294967295, fromUserLongName: "TBEAM ARMY GREEN", toUserLongName: "Unknown 1", fromUserShortName: "GVH", toUserShortName: "U1", receivedACK: false, messagePayload: "yo", direction: "received")
            
            
            
            
        ]
    }
}

extension MessageModel {
    struct Data {
        var id: UUID
        var messageId: UInt32
        var messageTimestamp: Int64
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
