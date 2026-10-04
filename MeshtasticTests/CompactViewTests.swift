//
//  CompactViewTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
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

@Suite("Node list row refresh decision", .serialized)
@MainActor
struct NodeListRowRefreshDecisionTests {
	private func makeNode() throws -> (ModelContainer, NodeInfoEntity) {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let node = NodeInfoEntity()
		node.num = 1
		node.lastHeard = Date(timeIntervalSince1970: 1_700_000_000)
		let user = UserEntity()
		user.num = 1
		user.longName = "Test Node"
		user.shortName = "TEST"
		node.user = user
		container.mainContext.insert(node)
		try container.mainContext.save()
		return (container, node)
	}

	private func constructionCount<V: View>(for view: V, container: ModelContainer) async -> Int {
		var count = 0
		NodeListRowSummary.testInitializationObserver = { count += 1 }
		defer { NodeListRowSummary.testInitializationObserver = nil }

		let hostingController = UIHostingController(rootView: view.modelContainer(container))
		let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 180))
		window.rootViewController = hostingController
		window.isHidden = false
		hostingController.view.frame = window.bounds
		hostingController.view.layoutIfNeeded()
		for _ in 0..<4 {
			await Task.yield()
		}
		window.isHidden = true
		return count
	}

	@Test func initialTaskDoesNotRefreshExistingSnapshot() {
		var gate = NodeListRowRefreshGate()
		let shouldRefresh = gate.shouldRefresh()

		#expect(!shouldRefresh)
	}

	@Test func subsequentTasksRefreshSnapshot() {
		var gate = NodeListRowRefreshGate()
		let initialShouldRefresh = gate.shouldRefresh()
		let secondShouldRefresh = gate.shouldRefresh()
		let thirdShouldRefresh = gate.shouldRefresh()

		#expect(!initialShouldRefresh)
		#expect(secondShouldRefresh)
		#expect(thirdShouldRefresh)
	}

	@Test func standardRowBuildsOneInitialSummary() async throws {
		let (container, node) = try makeNode()
		let count = await constructionCount(
			for: NodeListItem(node: node, isDirectlyConnected: false, connectedNode: 2),
			container: container
		)

		#expect(count == 1)
	}

	@Test func compactRowBuildsOneInitialSummary() async throws {
		let (container, node) = try makeNode()
		let count = await constructionCount(
			for: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 2),
			container: container
		)

		#expect(count == 1)
	}
}
