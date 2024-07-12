import SwiftUI

class AppState: ObservableObject {
	static let shared = AppState()

	@Published
	var tabSelection: Tab = .ble
	@Published
	var unreadDirectMessages: Int = 0
	@Published
	var unreadChannelMessages: Int = 0
	@Published
	var firmwareVersion: String = "0.0.0"
	@Published
	var navigationPath: String?
}
