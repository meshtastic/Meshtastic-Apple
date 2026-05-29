//
//  CompactViewTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import Testing
@testable import Meshtastic

// MARK: - NodeListDensity

@Suite("NodeListDensity")
struct NodeListDensityTests {

	@Test func caseCount() {
		#expect(NodeListDensity.allCases.count == 2)
	}

	@Test func standardDescription() {
		#expect(NodeListDensity.standard.description == "Complete".localized)
	}

	@Test func compactDescription() {
		#expect(NodeListDensity.compact.description == "Compact".localized)
	}

	@Test func identifiable() {
		#expect(NodeListDensity.standard.id == 0)
		#expect(NodeListDensity.compact.id == 1)
	}

	@Test func rawValues() {
		#expect(NodeListDensity(rawValue: 0) == .standard)
		#expect(NodeListDensity(rawValue: 1) == .compact)
		#expect(NodeListDensity(rawValue: 99) == nil)
	}
}

// MARK: - NodeListPreferences

@Suite("NodeListPreferences")
struct NodeListPreferencesTests {

	@Test func allPreferenceKeysExist() {
		let expected: [NodeListPreferences] = [
			.shouldShowRole,
			.shouldShowLocation,
			.shouldShowTelemetry,
			.shouldShowPower,
			.lastHeardIsRelative,
			.shouldShowLastHeard,
			.shouldShowChannel,
			.shouldShowHops,
			.shouldShowSignal
		]
		#expect(expected.count == 9)
	}

	@Test func rawValuesMatchPropertyNames() {
		#expect(NodeListPreferences.shouldShowRole.rawValue == "shouldShowRole")
		#expect(NodeListPreferences.shouldShowLocation.rawValue == "shouldShowLocation")
		#expect(NodeListPreferences.shouldShowTelemetry.rawValue == "shouldShowTelemetry")
		#expect(NodeListPreferences.shouldShowPower.rawValue == "shouldShowPower")
		#expect(NodeListPreferences.lastHeardIsRelative.rawValue == "lastHeardIsRelative")
		#expect(NodeListPreferences.shouldShowLastHeard.rawValue == "shouldShowLastHeard")
		#expect(NodeListPreferences.shouldShowChannel.rawValue == "shouldShowChannel")
		#expect(NodeListPreferences.shouldShowHops.rawValue == "shouldShowHops")
		#expect(NodeListPreferences.shouldShowSignal.rawValue == "shouldShowSignal")
	}

	@Test func rawValuesCanDriveAppStorage() {
		// Verify each raw value is a valid non-empty UserDefaults key
		let allPrefs: [NodeListPreferences] = [
			.shouldShowRole, .shouldShowLocation, .shouldShowTelemetry,
			.shouldShowPower, .lastHeardIsRelative, .shouldShowLastHeard,
			.shouldShowChannel, .shouldShowHops, .shouldShowSignal
		]
		for pref in allPrefs {
			#expect(!pref.rawValue.isEmpty)
		}
	}

	@Test func rawValuesAreUnique() {
		let allPrefs: [NodeListPreferences] = [
			.shouldShowRole, .shouldShowLocation, .shouldShowTelemetry,
			.shouldShowPower, .lastHeardIsRelative, .shouldShowLastHeard,
			.shouldShowChannel, .shouldShowHops, .shouldShowSignal
		]
		let unique = Set(allPrefs.map { $0.rawValue })
		#expect(unique.count == allPrefs.count)
	}
}
