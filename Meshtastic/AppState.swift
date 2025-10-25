import Combine
import SwiftUI
import UserNotifications
import UIKit

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
				let total = badgeCounts.0 + badgeCounts.1
				if #available(iOS 16, *) {
					UNUserNotificationCenter.current().setBadgeCount(total)
				} else {
					UIApplication.shared.applicationIconBadgeNumber = total
				}
			})
			.store(in: &cancellables)
	}
}
