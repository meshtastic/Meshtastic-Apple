import SwiftUI
import Testing
import UIKit
@testable import Meshtastic

@Suite("Migration bootstrap view")
@MainActor
struct MigrationBootstrapViewTests {
	@Test("Every configured app icon has light and dark thumbnails")
	func appIconAssetsExist() {
		let iconNames = AppIconPicker.iconOptions.map { $0.iconName ?? "AppIcon" }

		for iconName in iconNames {
			#expect(UIImage(named: "\(iconName)_Thumb") != nil)
			#expect(UIImage(named: "\(iconName)_Dark_Thumb") != nil)
		}
	}

	@Test("Missing alternate icon falls back to the default icon")
	func missingAlternateIconFallsBack() {
		#expect(MigrationBootstrapView.appIconImage(iconName: "MissingIcon", colorScheme: .light) != nil)
		#expect(MigrationBootstrapView.appIconImage(iconName: "MissingIcon", colorScheme: .dark) != nil)
	}

	@Test("Light and dark icons use different artwork")
	func appearanceSpecificIconsDiffer() throws {
		let lightData = try #require(MigrationBootstrapView.appIconImage(iconName: nil, colorScheme: .light)?.pngData())
		let darkData = try #require(MigrationBootstrapView.appIconImage(iconName: nil, colorScheme: .dark)?.pngData())
		#expect(lightData != darkData)
	}

	@Test("Migration and failure states provide VoiceOver announcements")
	func accessibilityAnnouncements() {
		#expect(
			PersistenceBootstrap.State.migrating.accessibilityAnnouncement ==
				"Updating local data. This may take a minute. Keep Meshtastic open."
		)
		#expect(
			PersistenceBootstrap.State.failed("details").accessibilityAnnouncement ==
				"Local data update failed. Retry is available."
		)
		#expect(PersistenceBootstrap.State.preparing.accessibilityAnnouncement == nil)
		#expect(PersistenceBootstrap.State.ready.accessibilityAnnouncement == nil)
	}
}
