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
	let exchangeRequested: Bool
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

	/// Posted when the radio reports something about a firmware update it was asked to start.
	/// The firmware answers an OTA request with a client notification saying what it did —
	/// rebooting into update mode, or why it would not: no OTA loader, a loader that does not
	/// do this transport, a bad hash. The update sheet shows it instead of waiting to time out
	/// on a device that was never coming. The message is the notification object.
	static let otaDeviceNotice = NSNotification.Name("OTADeviceNotice")
}

class AppState: ObservableObject {

	@Published var router: Router
	@Published var unreadChannelMessages: Int
	@Published var unreadDirectMessages: Int
	/// Bumped after a node-switch restore to force @Query-backed views to rebuild and
	/// refetch, so they drop objects cached from the previous node's database. Applied
	/// as `.id(appState.databaseResetID)` on the root content view.
	@Published var databaseResetID = UUID()
	/// True while a node switch is clearing/swapping the SwiftData container. ContentView
	/// replaces the whole tab tree with a lightweight non-SwiftData placeholder for the
	/// duration, so no @Query subscription exists while the store underneath it is cleared,
	/// destroyed, or repointed. Without this, the _SwiftData_SwiftUI bridge can process a
	/// store-change notification against the swapped-out context and trap (SIGTRAP,
	/// Datadog issue 324bff02-6b22-11f1, first seen 2.7.13 — the "repeatable crash when
	/// switching nodes"). The databaseResetID bump alone runs AFTER the swap, which is
	/// too late for subscriptions that are live during it.
	@Published var isDatabaseResetting = false
	/// Bumped immediately after the SwiftData container is recreated (repointToFreshContainer)
	/// so the scene body re-evaluates and `.modelContainer(...)` hands the NEW container to the
	/// environment. @Query subscriptions then re-bind in place — no view teardown. This is the
	/// counterpart to `databaseResetID`, which changes root identity and unmounts the whole
	/// tree: identity churn mid-switch is what produced the UIKit/CoreAnimation dead-view
	/// SIGTRAPs on device, so container delivery must never ride on it.
	@Published var containerStamp = UUID()
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
