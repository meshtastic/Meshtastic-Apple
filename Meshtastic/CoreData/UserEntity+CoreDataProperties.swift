//
//  UserEntity+CoreDataProperties.swift
//  
//
//  Created by Brian Floersch on 2/5/25.
//
//

import Foundation
import CoreData

extension UserEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserEntity> {
        return NSFetchRequest<UserEntity>(entityName: "UserEntity")
    }

    @NSManaged public var hwDisplayName: String?
    @NSManaged public var hwModel: String?
    @NSManaged public var hwModelId: Int32
    @NSManaged public var isLicensed: Bool
    @NSManaged public var keyMatch: Bool
    @NSManaged public var lastMessage: Date?
    @NSManaged public var longName: String?
    @NSManaged public var mute: Bool
    @NSManaged public var newPublicKey: Data?
    @NSManaged public var num: Int64
    @NSManaged public var numString: String?
    @NSManaged public var pkiEncrypted: Bool
    @NSManaged public var publicKey: Data?
    @NSManaged public var role: Int32
    @NSManaged public var shortName: String?
    @NSManaged public var userId: String?
    @NSManaged public var receivedMessages: NSOrderedSet?
    @NSManaged public var sentMessages: NSOrderedSet?
    @NSManaged public var userNode: NodeInfoEntity?

}

// MARK: Generated accessors for receivedMessages
extension UserEntity {

    @objc(insertObject:inReceivedMessagesAtIndex:)
    @NSManaged public func insertIntoReceivedMessages(_ value: MessageEntity, at idx: Int)

    @objc(removeObjectFromReceivedMessagesAtIndex:)
    @NSManaged public func removeFromReceivedMessages(at idx: Int)

    @objc(insertReceivedMessages:atIndexes:)
    @NSManaged public func insertIntoReceivedMessages(_ values: [MessageEntity], at indexes: NSIndexSet)

    @objc(removeReceivedMessagesAtIndexes:)
    @NSManaged public func removeFromReceivedMessages(at indexes: NSIndexSet)

    @objc(replaceObjectInReceivedMessagesAtIndex:withObject:)
    @NSManaged public func replaceReceivedMessages(at idx: Int, with value: MessageEntity)

    @objc(replaceReceivedMessagesAtIndexes:withReceivedMessages:)
    @NSManaged public func replaceReceivedMessages(at indexes: NSIndexSet, with values: [MessageEntity])

    @objc(addReceivedMessagesObject:)
    @NSManaged public func addToReceivedMessages(_ value: MessageEntity)

    @objc(removeReceivedMessagesObject:)
    @NSManaged public func removeFromReceivedMessages(_ value: MessageEntity)

    @objc(addReceivedMessages:)
    @NSManaged public func addToReceivedMessages(_ values: NSOrderedSet)

    @objc(removeReceivedMessages:)
    @NSManaged public func removeFromReceivedMessages(_ values: NSOrderedSet)

}

// MARK: Generated accessors for sentMessages
extension UserEntity {

    @objc(insertObject:inSentMessagesAtIndex:)
    @NSManaged public func insertIntoSentMessages(_ value: MessageEntity, at idx: Int)

    @objc(removeObjectFromSentMessagesAtIndex:)
    @NSManaged public func removeFromSentMessages(at idx: Int)

    @objc(insertSentMessages:atIndexes:)
    @NSManaged public func insertIntoSentMessages(_ values: [MessageEntity], at indexes: NSIndexSet)

    @objc(removeSentMessagesAtIndexes:)
    @NSManaged public func removeFromSentMessages(at indexes: NSIndexSet)

    @objc(replaceObjectInSentMessagesAtIndex:withObject:)
    @NSManaged public func replaceSentMessages(at idx: Int, with value: MessageEntity)

    @objc(replaceSentMessagesAtIndexes:withSentMessages:)
    @NSManaged public func replaceSentMessages(at indexes: NSIndexSet, with values: [MessageEntity])

    @objc(addSentMessagesObject:)
    @NSManaged public func addToSentMessages(_ value: MessageEntity)

    @objc(removeSentMessagesObject:)
    @NSManaged public func removeFromSentMessages(_ value: MessageEntity)

    @objc(addSentMessages:)
    @NSManaged public func addToSentMessages(_ values: NSOrderedSet)

    @objc(removeSentMessages:)
    @NSManaged public func removeFromSentMessages(_ values: NSOrderedSet)

}
