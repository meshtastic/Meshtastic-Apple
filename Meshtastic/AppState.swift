import Combine
import OSLog
@preconcurrency import SwiftData
import SwiftUI

class AppState: ObservableObject {

	@Published var router: Router
	@Published var unreadChannelMessages: Int
	@Published var unreadDirectMessages: Int
	/// Bumped after a node-switch restore to force @Query-backed views to rebuild and
	/// refetch, so they drop objects cached from the previous node's database. Applied
	/// as `.id(appState.databaseResetID)` on the root content view.
	@Published var databaseResetID = UUID()

	var totalUnreadMessages: Int {
		unreadChannelMessages + unreadDirectMessages
	}
	private var cancellables: Set<AnyCancellable> = []

	init(router: Router) {
		self.router = router
		self.unreadChannelMessages = 0
		self.unreadDirectMessages = 0

		// Keep app icon badge count in sync with messages read status
		$unreadChannelMessages.combineLatest($unreadDirectMessages)
			.sink(receiveValue: { badgeCounts in
				UNUserNotificationCenter.current()
					.setBadgeCount(badgeCounts.0 + badgeCounts.1)
			})
			.store(in: &cancellables)
	}

	/// Recalculate unread message counts from the database and update
	/// the app icon badge. Call this when the app becomes active or
	/// after any bulk read/delete operation to keep the badge in sync.
	@MainActor
	func refreshBadgeCount(context: ModelContext) {
		// NOTE: Comparing an optional relationship to nil in a #Predicate crashes SwiftData on
		// iOS 26 (SIGTRAP / heap corruption from the @Query machinery). Fetch all unread messages
		// and split channel vs DM in Swift — unread counts are small so this is inexpensive.
		let unreadDescriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.isEmoji == false && msg.read == false
			}
		)
		let unread = (try? context.fetch(unreadDescriptor)) ?? []
		// A muted ("Hide Alerts") channel or DM conversation is silent — exclude its unread
		// messages from every badge count (app icon + in-app Messages tab). A channel message is
		// muted when its channel index is muted; a DM is muted when the other party (fromUser) is
		// muted. Fetch the muted channel indexes once and filter in Swift to match the existing
		// pattern (comparing an optional relationship to nil in a #Predicate crashes SwiftData on
		// iOS 26, so the mute join stays out of the predicate too).
		let mutedChannelDescriptor = FetchDescriptor<ChannelEntity>(
			predicate: #Predicate<ChannelEntity> { $0.mute == true }
		)
		let mutedChannelIndexes = Set(((try? context.fetch(mutedChannelDescriptor)) ?? []).map { $0.index })
		let channelCount = unread.filter { $0.toUser == nil && !mutedChannelIndexes.contains($0.channel) }.count
		let dmCount = unread.filter { $0.toUser != nil && !$0.admin && !($0.fromUser?.mute ?? false) }.count
		if unreadChannelMessages != channelCount {
			unreadChannelMessages = channelCount
		}
		if unreadDirectMessages != dmCount {
			unreadDirectMessages = dmCount
		}
		Logger.data.debug("🔢 Badge refresh: \(channelCount) channel + \(dmCount) DM = \(channelCount + dmCount) total")
	}
}
