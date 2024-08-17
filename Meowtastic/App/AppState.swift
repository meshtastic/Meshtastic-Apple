import Combine
import SwiftUI

class AppState: ObservableObject {
	static let shared = AppState()

	@Published
	var tabSelection: TabTag = .nodes
	@Published
	var unreadDirectMessages = 0
	@Published
	var unreadChannelMessages = 0
	@Published
	var firmwareVersion = "0.0.0"
	@Published
	var navigationPath: String?

	private var cancellables: Set<AnyCancellable> = []

	init() {
		unreadChannelMessages = 0
		unreadDirectMessages = 0

		// Keep app icon badge count in sync with messages read status
		$unreadChannelMessages.combineLatest($unreadDirectMessages)
			.sink(receiveValue: { badgeCounts in
				UNUserNotificationCenter.current()
					.setBadgeCount(badgeCounts.0 + badgeCounts.1)
			})
			.store(in: &cancellables)
	}
}
