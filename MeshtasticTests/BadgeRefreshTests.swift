//
//  BadgeRefreshTests.swift
//  MeshtasticTests
//
//  Feature 021, review V40-4: the unread count behind the Dock badge follows message changes from
//  `AppState`, with no window of its own, so it keeps following them once the Mac's Connect window
//  has closed.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@MainActor
@Suite("The unread badge")
struct BadgeRefreshTests {
	@Test("The unread count follows message changes with no window showing, and isn't read during a store reset")
	func followsMessageChanges() async throws {
		let persistence = PersistenceController(inMemory: true, storeName: "BadgeRefresh-\(UUID().uuidString)")
		let appState = AppState()
		appState.refreshBadgeOnMessageChanges(persistence)
		let message = MessageEntity()
		message.read = false
		persistence.container.mainContext.insert(message)
		try persistence.container.mainContext.save()

		appState.isDatabaseResetting = true
		NotificationCenter.default.post(name: .meshMessagesDidChange, object: nil)
		try await Task.sleep(for: .milliseconds(1500))
		#expect(appState.unreadChannelMessages == 0, "not read during a reset")

		appState.isDatabaseResetting = false
		NotificationCenter.default.post(name: .meshMessagesDidChange, object: nil)
		for _ in 0..<40 where appState.unreadChannelMessages == 0 {
			try await Task.sleep(for: .milliseconds(100))
		}
		#expect(appState.unreadChannelMessages == 1)
	}
}
