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

    /// `ChannelEntity.unreadMessages` drives the in-app ChannelList unread indicator, so it must
    /// report the channel's true unread count regardless of mute. Muting ("Hide Alerts") only
    /// suppresses the notification + app-icon/Messages-tab badge, never the in-app unread state.
    @MainActor func testMutedChannelStillReportsUnreadInApp() throws {
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

        // Muted channel: in-app unread indicator still sees its real unread count.
        XCTAssertEqual(mutedChannel.unreadMessages(context: context), 2)
        // Unmuted channel: unaffected.
        XCTAssertEqual(unmutedChannel.unreadMessages(context: context), 1)
    }

    /// The app-icon / Messages-tab badge, on the other hand, must exclude muted channels. That
    /// filtering lives in the badge-aggregation path (`AppState.refreshBadgeCount`), so a muted
    /// channel's unread never reaches the badge even though it still shows in-app. Asserted as a
    /// delta (mute toggled on the same store state) so it stays robust against the shared
    /// in-memory test container carrying data from other tests.
    @MainActor func testBadgeCountExcludesMutedChannel() throws {
        let channelIndex: Int32 = 93

        let channel = ChannelEntity()
        channel.index = channelIndex
        channel.mute = false
        context.insert(channel)

        insertUnreadChannelMessage(channelIndex: channelIndex, messageId: 9_3001)
        insertUnreadChannelMessage(channelIndex: channelIndex, messageId: 9_3002)
        try context.save()

        let appState = AppState(router: Router())

        // Unmuted: the channel's 2 unread are included in the badge count.
        appState.refreshBadgeCount(context: context)
        let unmutedBadge = appState.unreadChannelMessages

        // Muting removes exactly this channel's 2 unread from the badge; all other store data,
        // and therefore every other channel's contribution, is unchanged between the two refreshes.
        channel.mute = true
        try context.save()
        appState.refreshBadgeCount(context: context)
        let mutedBadge = appState.unreadChannelMessages

        XCTAssertEqual(unmutedBadge - mutedBadge, 2)
    }
}
