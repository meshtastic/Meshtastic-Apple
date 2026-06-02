import Combine
import OSLog
@preconcurrency import SwiftData
import SwiftUI

class AppState: ObservableObject {

	@Published var router: Router
	@Published var unreadChannelMessages: Int
	@Published var unreadDirectMessages: Int

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
		let channelDescriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.toUser == nil && msg.isEmoji == false && msg.read == false
			}
		)
		let dmDescriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.toUser != nil && msg.isEmoji == false && msg.read == false && msg.admin == false
			}
		)
		let channelCount = (try? context.fetchCount(channelDescriptor)) ?? 0
		let dmCount = (try? context.fetchCount(dmDescriptor)) ?? 0
		if unreadChannelMessages != channelCount {
			unreadChannelMessages = channelCount
		}
		if unreadDirectMessages != dmCount {
			unreadDirectMessages = dmCount
		}
		Logger.data.debug("🔢 Badge refresh: \(channelCount) channel + \(dmCount) DM = \(channelCount + dmCount) total")
	}
}
