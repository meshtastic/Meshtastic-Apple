//
//  DeviceOnboardingTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import Testing
@testable import Meshtastic

// MARK: - SetupGuide Enum

@Suite("DeviceOnboarding.SetupGuide")
struct SetupGuideTests {

	@Test func allCasesExist() {
		let cases: [DeviceOnboarding.SetupGuide] = [
			.notifications, .location, .backgroundActivity,
			.localNetwork, .bluetooth, .siri
		]
		#expect(cases.count == 6)
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
		#expect(DeviceOnboarding.SetupGuide.location != .backgroundActivity)
	}

	@Test func allCasesAreUnique() {
		let cases: [DeviceOnboarding.SetupGuide] = [
			.notifications, .location, .backgroundActivity,
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

	private func firstStepIsValid(_ first: DeviceOnboarding.SetupGuide?) -> Bool {
		switch first {
		case .notifications, .location, .backgroundActivity:
			return true
		default:
			return false
		}
	}

	@Test func startRoutesToAnEarlyFlowStep() async {
		let view = DeviceOnboarding()
		await view.goToNextStep(after: nil)
		#expect(view.navigationPath.count == 1)
		#expect(firstStepIsValid(view.navigationPath.first))
	}

	@Test func notificationsRoutesToLocationOrBackgroundActivity() async {
		let view = DeviceOnboarding()
		await view.goToNextStep(after: .notifications)
		#expect(view.navigationPath.count == 1)
		#expect(view.navigationPath.first == .location || view.navigationPath.first == .backgroundActivity)
	}

	@Test func locationRoutesToBackgroundActivityWhenAuthorizedOrStays() async {
		let view = DeviceOnboarding()
		await view.goToNextStep(after: .location)
		#expect(view.navigationPath.isEmpty || view.navigationPath == [.backgroundActivity])
	}

	@Test func backgroundActivityAlwaysGoesToLocalNetwork() async {
		let view = DeviceOnboarding()
		await view.goToNextStep(after: .backgroundActivity)
		#expect(view.navigationPath == [.localNetwork])
	}

	@Test func localNetworkAlwaysGoesToBluetooth() async {
		let view = DeviceOnboarding()
		await view.goToNextStep(after: .localNetwork)
		#expect(view.navigationPath == [.bluetooth])
	}

	@Test func bluetoothAlwaysGoesToSiri() async {
		let view = DeviceOnboarding()
		await view.goToNextStep(after: .bluetooth)
		#expect(view.navigationPath == [.siri])
	}

	@Test func navigationPathStartsEmpty() {
		let view = DeviceOnboarding()
		#expect(view.navigationPath.isEmpty)
	}

	@Test func deterministicStepsAppendInOrder() async {
		let view = DeviceOnboarding()
		await view.goToNextStep(after: .backgroundActivity)
		await view.goToNextStep(after: .localNetwork)
		await view.goToNextStep(after: .bluetooth)
		#expect(view.navigationPath == [.localNetwork, .bluetooth, .siri])
	}

	@Test func fullDeterministicTailFromBackgroundToSiri() async {
		let view = DeviceOnboarding()
		await view.goToNextStep(after: .backgroundActivity)
		await view.goToNextStep(after: .localNetwork)
		await view.goToNextStep(after: .bluetooth)
		#expect(view.navigationPath.last == .siri)
	}
}
