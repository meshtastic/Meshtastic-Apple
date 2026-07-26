import Combine
import MeshtasticProtobufs
import OSLog
@preconcurrency import SwiftData
import SwiftUI

/// A contact parsed from a shared contact URL, waiting for the user to
/// confirm the import. The original base64url payload is kept so the
/// encoded `manually_verified` bit reaches the radio untouched.
struct PendingContact: Identifiable {
	let id = UUID()
	let contact: SharedContact
	let base64UrlString: String
}

extension NSNotification.Name {
	/// Posted whenever message read-state changes anywhere (new message saved,
	/// messages marked read in a list, Siri/CarPlay read-aloud). Observers that
	/// display unread state (badge counts, the CarPlay list templates) refresh on
	/// it — before this existed the CarPlay templates only refreshed on
	/// connect/disconnect and went stale for the whole drive.
	/// (NSNotification.Name, not Notification.Name — the app defines its own
	/// `Notification` model type which shadows Foundation's in some files.)
	static let meshMessagesDidChange = NSNotification.Name("MeshMessagesDidChange")
}

class AppState: ObservableObject {

	@Published var router: Router
	@Published var unreadChannelMessages: Int
	@Published var unreadDirectMessages: Int
	/// Bumped after a node-switch restore to force @Query-backed views to rebuild and
	/// refetch, so they drop objects cached from the previous node's database. Applied
	/// as `.id(appState.databaseResetID)` on the root content view.
	@Published var databaseResetID = UUID()
	/// A contact parsed from a meshtastic.org/v/# URL (QR code, link, or NFC tag)
	/// awaiting user confirmation. Presented as a sheet from MeshtasticApp, the
	/// same pattern the channel-link import uses.
	@Published var pendingContactToAdd: PendingContact?

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
		let channelCount = unread.filter { $0.toUser == nil }.count
		let dmCount = unread.filter { $0.toUser != nil && !$0.admin }.count
		if unreadChannelMessages != channelCount {
			unreadChannelMessages = channelCount
		}
		if unreadDirectMessages != dmCount {
			unreadDirectMessages = dmCount
		}
		Logger.data.debug("🔢 Badge refresh: \(channelCount) channel + \(dmCount) DM = \(channelCount + dmCount) total")
	}
}
