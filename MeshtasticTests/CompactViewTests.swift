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

// MARK: - NodeListRefreshState

@Suite("NodeListRefreshState")
struct NodeListRefreshStateTests {

	@Test func startsWithPendingRefresh() {
		let state = NodeListRefreshState()

		#expect(state.needsRefresh)
		#expect(state.canRefresh)
	}

	@Test func completedRefreshWaitsForAnotherChange() {
		var state = NodeListRefreshState()

		state.didRefresh(succeeded: true)

		#expect(!state.needsRefresh)
		#expect(!state.canRefresh)
		state.setNeedsRefresh()
		#expect(state.needsRefresh)
		#expect(state.canRefresh)
	}

	@Test func failedRefreshRemainsPending() {
		var state = NodeListRefreshState()
		state.didRefresh(succeeded: true)

		state.didRefresh(succeeded: false)

		#expect(state.needsRefresh)
		#expect(state.canRefresh)
	}

	@Test func scrollingDefersPendingRefresh() {
		var state = NodeListRefreshState()

		state.setScrolling(true)

		#expect(state.needsRefresh)
		#expect(!state.canRefresh)
		state.setScrolling(false)
		#expect(state.canRefresh)
	}

	@Test func scrollingDoesNotRequestRefresh() {
		var state = NodeListRefreshState()
		state.didRefresh(succeeded: true)

		state.setScrolling(true)
		state.setScrolling(false)

		#expect(!state.needsRefresh)
		#expect(!state.canRefresh)
	}

	@Test func changesWhileScrollingRemainPending() {
		var state = NodeListRefreshState()
		state.didRefresh(succeeded: true)
		state.setScrolling(true)

		state.setNeedsRefresh()
		state.setNeedsRefresh()

		#expect(state.needsRefresh)
		#expect(!state.canRefresh)
		state.setScrolling(false)
		#expect(state.canRefresh)
	}

	@Test func refreshPipelineDefersSideEffectUntilScrollingEnds() {
		var state = NodeListRefreshState()
		var refreshCallCount = 0
		let refresh = {
			refreshCallCount += 1
			return true
		}

		state.setScrolling(true)
		let scrollingResult = state.runRefreshIfNeeded(refresh)

		#expect(scrollingResult == nil)
		#expect(refreshCallCount == 0)

		state.setScrolling(false)
		if let succeeded = state.runRefreshIfNeeded(refresh) {
			state.didRefresh(succeeded: succeeded)
		}

		#expect(refreshCallCount == 1)
		#expect(!state.needsRefresh)
	}

	@Test @MainActor func onlineAgingUsesMinuteCadence() async {
		var requestedIntervals: [Duration] = []
		var refreshCallCount = 0

		await runOnlineNodeAgingTask(
			isEnabled: true,
			sleep: { interval in
				requestedIntervals.append(interval)
				if requestedIntervals.count > 1 {
					throw CancellationError()
				}
			},
			markRefreshNeeded: {
				refreshCallCount += 1
			}
		)

		#expect(requestedIntervals == [.seconds(60), .seconds(60)])
		#expect(refreshCallCount == 1)
	}

	@Test @MainActor func onlineAgingStopsWhenDisabled() async {
		var sleepCallCount = 0
		var refreshCallCount = 0

		await runOnlineNodeAgingTask(
			isEnabled: false,
			sleep: { _ in
				sleepCallCount += 1
			},
			markRefreshNeeded: {
				refreshCallCount += 1
			}
		)

		#expect(sleepCallCount == 0)
		#expect(refreshCallCount == 0)
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
