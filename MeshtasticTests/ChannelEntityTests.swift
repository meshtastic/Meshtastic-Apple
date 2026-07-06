import XCTest
import SwiftData
@testable import Meshtastic

final class ChannelEntityTests: XCTestCase {
    var modelContainer: ModelContainer!
    var context: ModelContext!

    @MainActor override func setUp() {
        super.setUp()
        modelContainer = sharedModelContainer
        context = ModelContext(modelContainer)
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    func testChannelEntityDefaultInit() {
        let channel = ChannelEntity()
        XCTAssertFalse(channel.downlinkEnabled)
        XCTAssertEqual(channel.id, 0)
        XCTAssertEqual(channel.index, 0)
        XCTAssertFalse(channel.mute)
        XCTAssertNil(channel.name)
        XCTAssertEqual(channel.positionPrecision, 32)
        XCTAssertNil(channel.psk)
        XCTAssertEqual(channel.role, 0)
        XCTAssertFalse(channel.uplinkEnabled)
        XCTAssertNil(channel.myInfoChannel)
    }

    func testChannelEntityInsertAndFetch() throws {
        let channel = ChannelEntity()
        channel.id = 42
        channel.name = "Test Channel"
        channel.uplinkEnabled = true
        context.insert(channel)
        try context.save()

        let descriptor = FetchDescriptor<ChannelEntity>(predicate: #Predicate { $0.id == 42 })
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Test Channel")
        XCTAssertTrue(fetched.first?.uplinkEnabled ?? false)
    }

    /// Inserts an unread channel broadcast (toUser == nil, not an emoji/tapback) on `channelIndex`.
    @MainActor private func insertUnreadChannelMessage(channelIndex: Int32, messageId: Int64) {
        let message = MessageEntity()
        message.messageId = messageId
        message.channel = channelIndex
        message.isEmoji = false
        message.read = false
        message.toUser = nil
        context.insert(message)
    }

    /// A muted ("Hide Alerts") channel must report zero unread so it never badges the app icon or
    /// the in-app Messages tab, while an unmuted channel still reports its real unread count.
    @MainActor func testMutedChannelReportsZeroUnread() throws {
        let mutedIndex: Int32 = 91
        let unmutedIndex: Int32 = 92

        let mutedChannel = ChannelEntity()
        mutedChannel.index = mutedIndex
        mutedChannel.mute = true
        context.insert(mutedChannel)

        let unmutedChannel = ChannelEntity()
        unmutedChannel.index = unmutedIndex
        unmutedChannel.mute = false
        context.insert(unmutedChannel)

        insertUnreadChannelMessage(channelIndex: mutedIndex, messageId: 9_1001)
        insertUnreadChannelMessage(channelIndex: mutedIndex, messageId: 9_1002)
        insertUnreadChannelMessage(channelIndex: unmutedIndex, messageId: 9_2001)
        try context.save()

        // Muted channel: silent — contributes zero to the badge.
        XCTAssertEqual(mutedChannel.unreadMessages(context: context), 0)
        // Unmuted channel: unaffected by the mute filter.
        XCTAssertEqual(unmutedChannel.unreadMessages(context: context), 1)

        // Un-muting the channel restores its unread count.
        mutedChannel.mute = false
        XCTAssertEqual(mutedChannel.unreadMessages(context: context), 2)
    }
}
