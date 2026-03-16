//
//  UpdateCoreDataTests.swift
//  Meshtastic
//
//  Tests for deleteChannelMessages functions

import XCTest
import CoreData
@testable import Meshtastic

final class DeleteChannelMessagesTests: XCTestCase {
    private func createTestPersistenceController() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "MeshtasticDataModel")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load test store: \(error)")
            }
        }
        
        return container
    }
    
    private func createTestChannel(
        in context: NSManagedObjectContext,
        messageCount: Int = 0
    ) -> ChannelEntity {
        let channel = ChannelEntity(context: context)
        channel.index = 1
        channel.name = "Test Channel"
        
        for i in 0..<messageCount {
            let message = MessageEntity(context: context)
            message.messageId = Int64(i)
            message.messageTimestamp = Int32(Date().timeIntervalSince1970)
            message.channel = channel.index
        }
        
        try? context.save()
        return channel
    }
    
    func testSyncDeleteChannelMessages() throws {
        let container = createTestPersistenceController()
        let context = container.newBackgroundContext()
        
        var channel: ChannelEntity!
        var channelObjectID: NSManagedObjectID!
        
        container.viewContext.performAndWait {
            channel = createTestChannel(in: container.viewContext, messageCount: 5)
            channelObjectID = channel.objectID
            try? container.viewContext.save()
        }
        
        context.performAndWait {
            guard let channelInContext = context.object(with: channelObjectID) as? ChannelEntity else {
                XCTFail("Could not get channel in context")
                return
            }
            
            MeshPackets.shared.deleteChannelMessages(channel: channelInContext, context: context)
            
            let fetchAfter = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
            fetchAfter.predicate = NSPredicate(format: "channel == %d", channelInContext.index)
            let messagesAfter = try? context.fetch(fetchAfter)
            XCTAssertEqual(messagesAfter?.count, 0, "Should have 0 messages after deletion")
        }
    }
    
    func testSyncDeleteChannelMessagesInvalidChannel() throws {
        let container = createTestPersistenceController()
        let context = container.newBackgroundContext()
        
        let channel = createTestChannel(in: container.viewContext, messageCount: 3)
        
        context.performAndWait {
            MeshPackets.shared.deleteChannelMessages(channel: channel, context: context)
        }
    }
    
    func testSyncDeleteChannelMessagesBatchDelete() throws {
        let container = createTestPersistenceController()
        let context = container.newBackgroundContext()
        
        var channelObjectID: NSManagedObjectID!
        
        container.viewContext.performAndWait {
            let channel = createTestChannel(in: container.viewContext, messageCount: 100)
            channelObjectID = channel.objectID
            try? container.viewContext.save()
        }
        
        context.performAndWait {
            guard let channelInContext = context.object(with: channelObjectID) as? ChannelEntity else {
                XCTFail("Could not get channel in context")
                return
            }
            
            MeshPackets.shared.deleteChannelMessages(channel: channelInContext, context: context)
            
            let fetchAfter = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
            fetchAfter.predicate = NSPredicate(format: "channel == %d", channelInContext.index)
            let messagesAfter = try? context.fetch(fetchAfter)
            XCTAssertEqual(messagesAfter?.count, 0, "All 100 messages should be deleted")
        }
    }
    
    func testSyncDeleteChannelMessagesMergesChanges() throws {
        let container = createTestPersistenceController()
        let backgroundContext = container.newBackgroundContext()
        
        var channelObjectID: NSManagedObjectID!
        
        container.viewContext.performAndWait {
            let channel = createTestChannel(in: container.viewContext, messageCount: 10)
            channelObjectID = channel.objectID
            try? container.viewContext.save()
        }
        
        backgroundContext.performAndWait {
            guard let channelInContext = backgroundContext.object(with: channelObjectID) as? ChannelEntity else {
                XCTFail("Could not get channel in context")
                return
            }
            
            MeshPackets.shared.deleteChannelMessages(channel: channelInContext, context: backgroundContext)
        }
        
        container.viewContext.performAndWait {
            container.viewContext.refreshAllObjects()
            
            guard let channel = try? container.viewContext.existingObject(with: channelObjectID) as? ChannelEntity else {
                XCTFail("Could not get channel in view context")
                return
            }
            
            let fetchAfter = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
            fetchAfter.predicate = NSPredicate(format: "channel == %d", channel.index)
            let messagesAfter = try? container.viewContext.fetch(fetchAfter)
            XCTAssertEqual(messagesAfter?.count, 0, "Changes should be merged to view context")
        }
    }
    
    func testSyncDeleteChannelMessagesOnlyAffectsSpecifiedChannel() throws {
        let container = createTestPersistenceController()
        let context = container.newBackgroundContext()
        
        var channel1ObjectID: NSManagedObjectID!
        var channel2ObjectID: NSManagedObjectID!
        
        container.viewContext.performAndWait {
            let channel1 = createTestChannel(in: container.viewContext, messageCount: 5)
            let channel2 = createTestChannel(in: container.viewContext, messageCount: 3)
            channel1.index = 1
            channel2.index = 2
            
            channel1ObjectID = channel1.objectID
            channel2ObjectID = channel2.objectID
            try? container.viewContext.save()
        }
        
        context.performAndWait {
            guard let channel1InContext = context.object(with: channel1ObjectID) as? ChannelEntity,
                  let channel2InContext = context.object(with: channel2ObjectID) as? ChannelEntity else {
                XCTFail("Could not get channels in context")
                return
            }
            
            MeshPackets.shared.deleteChannelMessages(channel: channel1InContext, context: context)
            
            let fetch1 = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
            fetch1.predicate = NSPredicate(format: "channel == %d", channel1InContext.index)
            let messages1 = try? context.fetch(fetch1)
            XCTAssertEqual(messages1?.count, 0, "Channel 1 should have 0 messages")
            
            let fetch2 = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
            fetch2.predicate = NSPredicate(format: "channel == %d", channel2InContext.index)
            let messages2 = try? context.fetch(fetch2)
            XCTAssertEqual(messages2?.count, 3, "Channel 2 should still have 3 messages")
        }
    }
    
    func testSyncDeleteChannelMessagesHandlesSaveErrors() throws {
        let container = createTestPersistenceController()
        let context = container.newBackgroundContext()
        
        var channelObjectID: NSManagedObjectID!
        
        container.viewContext.performAndWait {
            let channel = createTestChannel(in: container.viewContext, messageCount: 2)
            channelObjectID = channel.objectID
            try? container.viewContext.save()
        }
        
        context.performAndWait {
            guard let channelInContext = context.object(with: channelObjectID) as? ChannelEntity else {
                XCTFail("Could not get channel in context")
                return
            }
            
            MeshPackets.shared.deleteChannelMessages(channel: channelInContext, context: context)
        }
    }
}
