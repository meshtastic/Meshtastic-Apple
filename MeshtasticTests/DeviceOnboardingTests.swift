//
//  DeviceOnboardingTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import CoreLocation
import UserNotifications
import Testing
@testable import Meshtastic

// MARK: - SetupGuide Enum

@Suite("DeviceOnboarding.SetupGuide")
struct SetupGuideTests {

	@Test func allCasesExist() {
		let cases: [DeviceOnboarding.SetupGuide] = [
			.notifications, .location,
			.localNetwork, .bluetooth, .siri
		]
		#expect(cases.count == 5)
	}

	@Test func isHashable() {
		var seen = Set<DeviceOnboarding.SetupGuide>()
		seen.insert(.notifications)
		seen.insert(.notifications) // duplicate should not grow set
		seen.insert(.siri)
		#expect(seen.count == 2)
	}

	@Test func equality() {
		#expect(DeviceOnboarding.SetupGuide.bluetooth == .bluetooth)
		#expect(DeviceOnboarding.SetupGuide.notifications != .siri)
		#expect(DeviceOnboarding.SetupGuide.location != .localNetwork)
	}

	@Test func allCasesAreUnique() {
		let cases: [DeviceOnboarding.SetupGuide] = [
			.notifications, .location,
			.localNetwork, .bluetooth, .siri
		]
		let unique = Set(cases)
		#expect(unique.count == cases.count)
	}
}

// MARK: - Attributed String Formatters

@Suite("DeviceOnboarding string formatters")
struct OnboardingStringFormatterTests {

	let view = DeviceOnboarding()

	// Helpers
	private func hasSettingsLink(_ string: AttributedString) -> Bool {
		guard let range = string.range(of: "settings") else { return false }
		return string[range].link != nil
	}

	private func settingsLinkURL(_ string: AttributedString) -> URL? {
		guard let range = string.range(of: "settings") else { return nil }
		return string[range].link
	}

	@Test func backgroundActivityStringContainsText() {
		let string = view.createBackgroundActivityString()
		#expect(string.description.contains("background"))
		#expect(string.description.contains("settings"))
	}

	@Test func backgroundActivityStringHasSettingsLink() {
		let string = view.createBackgroundActivityString()
		#expect(hasSettingsLink(string))
	}

	@Test func backgroundActivitySettingsLinkIsAppSettings() {
		let string = view.createBackgroundActivityString()
		let url = settingsLinkURL(string)
		#expect(url?.scheme == "app-settings" || url?.absoluteString.contains("settings") == true)
	}

	@Test func locationStringContainsText() {
		let string = view.createLocationString()
		#expect(string.description.contains("location"))
		#expect(string.description.contains("settings"))
	}

	@Test func locationStringHasSettingsLink() {
		let string = view.createLocationString()
		#expect(hasSettingsLink(string))
	}

	@Test func localNetworkStringContainsText() {
		let string = view.createLocalNetworkString()
		#expect(string.description.contains("local network") || string.description.contains("TCP"))
		#expect(string.description.contains("settings"))
	}

	@Test func localNetworkStringHasSettingsLink() {
		let string = view.createLocalNetworkString()
		#expect(hasSettingsLink(string))
	}

	@Test func bluetoothStringContainsText() {
		let string = view.createBluetoothString()
		#expect(string.description.contains("Bluetooth") || string.description.contains("BLE"))
		#expect(string.description.contains("settings"))
	}

	@Test func bluetoothStringHasSettingsLink() {
		let string = view.createBluetoothString()
		#expect(hasSettingsLink(string))
	}

	@Test func siriStringContainsCarPlay() {
		let string = view.createSiriString()
		#expect(string.description.contains("CarPlay"))
	}

	@Test func siriStringContainsSiri() {
		let string = view.createSiriString()
		#expect(string.description.contains("Siri"))
	}

	@Test func siriStringHasSettingsLink() {
		let string = view.createSiriString()
		#expect(hasSettingsLink(string))
	}

	@Test func allStringsHaveSettingsLinks() {
		let strings = [
			view.createBackgroundActivityString(),
			view.createLocationString(),
			view.createLocalNetworkString(),
			view.createBluetoothString(),
			view.createSiriString()
		]
		for string in strings {
			#expect(hasSettingsLink(string), "Expected 'settings' link in: \(string)")
		}
	}
}

// MARK: - Navigation Flow

@Suite("DeviceOnboarding navigation")
struct OnboardingNavigationTests {

	private func nextStep(
		after step: DeviceOnboarding.SetupGuide?,
		notificationStatus: UNAuthorizationStatus,
		criticalAlertSetting: UNNotificationSetting,
		locationStatus: CLAuthorizationStatus
	) -> DeviceOnboarding.SetupGuide? {
		let view = DeviceOnboarding()
		return view.nextStep(
			after: step,
			notificationStatus: notificationStatus,
			criticalAlertSetting: criticalAlertSetting,
			locationStatus: locationStatus
		)
	}

	@Test func startRoutesToNotificationsWhenNotificationsUnknown() {
		let step = nextStep(
			after: nil,
			notificationStatus: .notDetermined,
			criticalAlertSetting: .notSupported,
			locationStatus: .authorizedAlways
		)
		#expect(step == .notifications)
	}

	@Test func startRoutesToLocationWhenNotificationsKnownAndLocationDenied() {
		let step = nextStep(
			after: nil,
			notificationStatus: .authorized,
			criticalAlertSetting: .enabled,
			locationStatus: .denied
		)
		#expect(step == .location)
	}

	@Test func startRoutesToBluetoothWhenLocationAuthorized() {
		let step = nextStep(
			after: nil,
			notificationStatus: .authorized,
			criticalAlertSetting: .enabled,
			locationStatus: .authorizedWhenInUse
		)
		#expect(step == .bluetooth)
	}

	@Test func notificationsRoutesToLocationOrBluetooth() {
		let denied = nextStep(
			after: .notifications,
			notificationStatus: .authorized,
			criticalAlertSetting: .enabled,
			locationStatus: .denied
		)
		let authorized = nextStep(
			after: .notifications,
			notificationStatus: .authorized,
			criticalAlertSetting: .enabled,
			locationStatus: .authorizedAlways
		)
		#expect(denied == .location)
		#expect(authorized == .bluetooth)
	}

	@Test func locationRoutesToBluetooth() {
		let authorized = nextStep(
			after: .location,
			notificationStatus: .authorized,
			criticalAlertSetting: .enabled,
			locationStatus: .authorizedAlways
		)
		let denied = nextStep(
			after: .location,
			notificationStatus: .authorized,
			criticalAlertSetting: .enabled,
			locationStatus: .denied
		)
		#expect(authorized == .bluetooth)
		#expect(denied == .bluetooth)
	}

	@Test func deterministicTailFlowMapping() {
		#expect(nextStep(after: .bluetooth, notificationStatus: .authorized, criticalAlertSetting: .enabled, locationStatus: .authorizedAlways) == .localNetwork)
		#expect(nextStep(after: .localNetwork, notificationStatus: .authorized, criticalAlertSetting: .enabled, locationStatus: .authorizedAlways) == .siri)
		#expect(nextStep(after: .siri, notificationStatus: .authorized, criticalAlertSetting: .enabled, locationStatus: .authorizedAlways) == nil)
	}
}
