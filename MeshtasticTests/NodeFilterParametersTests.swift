//
//  NodeFilterParametersTests.swift
//  Meshtastic
//
//  Created on 3/16/26.
//

import Combine
import CoreLocation
import Foundation
import SwiftData
import Testing

@testable import Meshtastic

/// Creates an isolated `UserDefaults` suite for a test, cleared of any prior state.
///
/// Using a dedicated suite (rather than `UserDefaults.standard`) keeps each test from reading or
/// clobbering global defaults — which would be fragile and could interfere with other tests
/// running in parallel. The suite is injected into `NodeFilterParameters(store:)`.
@MainActor
private func makeIsolatedDefaults(_ suiteName: String) -> UserDefaults {
	let defaults = UserDefaults(suiteName: suiteName)!
	defaults.removePersistentDomain(forName: suiteName)
	return defaults
}

@MainActor
@Suite("NodeFilterParameters", .serialized)
struct NodeFilterParametersTests {

	/// Isolated defaults store, injected into every `NodeFilterParameters` under test.
	let defaults: UserDefaults

	init() {
		defaults = makeIsolatedDefaults("NodeFilterParametersTests.persistence")
	}

	// MARK: - Initialization Tests

	@Test("Default initialization uses expected defaults")
	func defaultInitialization() {
		let filters = NodeFilterParameters(store: defaults)

		#expect(filters.searchText == "")
		#expect(filters.isOnline == false)
		#expect(filters.isPkiEncrypted == false)
		#expect(filters.isFavorite == false)
		#expect(filters.isIgnored == false)
		#expect(filters.isEnvironment == false)
		#expect(filters.distanceFilter == false)
		#expect(filters.maxDistance == 800_000)
		#expect(filters.hopsAway == -1.0)
		#expect(filters.roleFilter == false)
		#expect(filters.deviceRoles.isEmpty)
		#expect(filters.viaLora == true)
		#expect(filters.viaMqtt == true)
	}

	@Test("Initialization loads persisted device roles")
	func initializationWithPersistedDeviceRoles() {
		// Store device roles in UserDefaults
		let expectedRoles = [1, 2, 3, 5, 8]
		defaults.set(expectedRoles, forKey: "nodeFilter.deviceRoles")

		let filters = NodeFilterParameters(store: defaults)

		#expect(filters.deviceRoles == Set(expectedRoles))
	}

	// MARK: - Persistence Tests

	@Test("Search text is not persisted across instances")
	func searchTextIsNotPersisted() {
		let filters1 = NodeFilterParameters(store: defaults)
		filters1.searchText = "Test Node"

		// searchText is intentionally session-only — a stale search on relaunch hides most nodes.
		let filters2 = NodeFilterParameters(store: defaults)
		#expect(filters2.searchText == "")
	}

	@Test("Boolean filters persist across instances")
	func booleanFiltersPersistence() {
		let filters1 = NodeFilterParameters(store: defaults)
		filters1.isOnline = true
		filters1.isPkiEncrypted = true
		filters1.isFavorite = true
		filters1.isIgnored = true
		filters1.isEnvironment = true
		filters1.distanceFilter = true
		filters1.roleFilter = true

		let filters2 = NodeFilterParameters(store: defaults)
		#expect(filters2.isOnline == true)
		#expect(filters2.isPkiEncrypted == true)
		#expect(filters2.isFavorite == true)
		#expect(filters2.isIgnored == true)
		#expect(filters2.isEnvironment == true)
		#expect(filters2.distanceFilter == true)
		#expect(filters2.roleFilter == true)
	}

	@Test("Numeric filters persist across instances")
	func numericFiltersPersistence() {
		let filters1 = NodeFilterParameters(store: defaults)
		filters1.maxDistance = 500_000
		filters1.hopsAway = 3.0

		let filters2 = NodeFilterParameters(store: defaults)
		#expect(filters2.maxDistance == 500_000)
		#expect(filters2.hopsAway == 3.0)
	}

	// MARK: - Device Roles Tests

	@Test("Device roles persist to UserDefaults and new instances")
	func deviceRolesPersistence() throws {
		let filters1 = NodeFilterParameters(store: defaults)
		filters1.deviceRoles = [1, 3, 5, 7]

		// Verify it's stored in UserDefaults
		let storedRoles = try #require(defaults.array(forKey: "nodeFilter.deviceRoles") as? [Int])
		#expect(Set(storedRoles) == Set([1, 3, 5, 7]))

		// Verify it persists to new instance
		let filters2 = NodeFilterParameters(store: defaults)
		#expect(filters2.deviceRoles == Set([1, 3, 5, 7]))
	}

	@Test("Adding device roles persists")
	func addingDeviceRoles() {
		let filters = NodeFilterParameters(store: defaults)
		filters.deviceRoles.insert(2)
		filters.deviceRoles.insert(4)
		filters.deviceRoles.insert(6)

		let newFilters = NodeFilterParameters(store: defaults)
		#expect(newFilters.deviceRoles.contains(2))
		#expect(newFilters.deviceRoles.contains(4))
		#expect(newFilters.deviceRoles.contains(6))
		#expect(newFilters.deviceRoles.count == 3)
	}

	@Test("Removing device roles persists")
	func removingDeviceRoles() {
		let filters1 = NodeFilterParameters(store: defaults)
		filters1.deviceRoles = [1, 2, 3, 4, 5]

		filters1.deviceRoles.remove(2)
		filters1.deviceRoles.remove(4)

		let filters2 = NodeFilterParameters(store: defaults)
		#expect(filters2.deviceRoles == Set([1, 3, 5]))
		#expect(!filters2.deviceRoles.contains(2))
		#expect(!filters2.deviceRoles.contains(4))
	}

	@Test("Empty device roles persist")
	func emptyDeviceRolesPersistence() {
		let filters1 = NodeFilterParameters(store: defaults)
		filters1.deviceRoles = [1, 2, 3]

		// Clear the set
		filters1.deviceRoles = []

		let filters2 = NodeFilterParameters(store: defaults)
		#expect(filters2.deviceRoles.isEmpty)
	}

	// MARK: - Via Lora/MQTT Enforcement Tests

	@Test("Disabling viaLora keeps viaMqtt enabled")
	func viaLoraEnforcesViaMqtt() {
		let filters = NodeFilterParameters(store: defaults)

		// Start with both true
		#expect(filters.viaLora == true)
		#expect(filters.viaMqtt == true)

		// Set viaLora to false
		filters.viaLora = false

		// viaMqtt should remain true
		#expect(filters.viaLora == false)
		#expect(filters.viaMqtt == true)

		// Try to set viaMqtt to false - it should enforce viaLora to true
		filters.viaMqtt = false

		#expect(filters.viaLora == true)
		#expect(filters.viaMqtt == false)
	}

	@Test("Disabling viaMqtt keeps viaLora enabled")
	func viaMqttEnforcesViaLora() {
		let filters = NodeFilterParameters(store: defaults)

		// Start with both true
		#expect(filters.viaLora == true)
		#expect(filters.viaMqtt == true)

		// Set viaMqtt to false
		filters.viaMqtt = false

		// viaLora should remain true
		#expect(filters.viaLora == true)
		#expect(filters.viaMqtt == false)

		// Try to set viaLora to false - it should enforce viaMqtt to true
		filters.viaLora = false

		#expect(filters.viaLora == false)
		#expect(filters.viaMqtt == true)
	}

	@Test("Both via options can be true")
	func bothViaTrue() {
		let filters = NodeFilterParameters(store: defaults)
		filters.viaLora = true
		filters.viaMqtt = true

		#expect(filters.viaLora == true)
		#expect(filters.viaMqtt == true)
	}

	@Test("Via settings persist across instances")
	func viaSettingsPersistence() {
		let filters1 = NodeFilterParameters(store: defaults)
		filters1.viaLora = false
		// viaMqtt should be enforced to true

		let filters2 = NodeFilterParameters(store: defaults)
		#expect(filters2.viaLora == false)
		#expect(filters2.viaMqtt == true)
	}

	@Test("Cannot have both via options false")
	func cannotHaveBothViaFalse() {
		let filters = NodeFilterParameters(store: defaults)

		// Set viaLora to false first
		filters.viaLora = false
		#expect(filters.viaLora == false)
		#expect(filters.viaMqtt == true)

		// Try to set viaMqtt to false
		filters.viaMqtt = false

		// viaLora should be enforced back to true
		#expect(filters.viaLora == true)
		#expect(filters.viaMqtt == false)
	}

	// MARK: - ObservableObject Tests

	@Test("Mutations publish objectWillChange")
	func objectWillChange() {
		let filters = NodeFilterParameters(store: defaults)
		var changeCount = 0

		let cancellable = filters.objectWillChange.sink {
			changeCount += 1
		}

		// Modify various properties
		filters.searchText = "Test"
		filters.isOnline = true
		filters.deviceRoles.insert(1)
		filters.viaLora = false

		// Should have triggered changes
		#expect(changeCount > 0)

		cancellable.cancel()
	}

	// MARK: - Edge Cases

	@Test("Large maxDistance persists")
	func largeMaxDistance() {
		let filters = NodeFilterParameters(store: defaults)
		filters.maxDistance = 10_000_000

		let newFilters = NodeFilterParameters(store: defaults)
		#expect(newFilters.maxDistance == 10_000_000)
	}

	@Test("Negative hopsAway persists")
	func negativeHopsAway() {
		let filters = NodeFilterParameters(store: defaults)
		filters.hopsAway = -1.0

		let newFilters = NodeFilterParameters(store: defaults)
		#expect(newFilters.hopsAway == -1.0)
	}

	@Test("Zero hopsAway persists")
	func zeroHopsAway() {
		let filters = NodeFilterParameters(store: defaults)
		filters.hopsAway = 0.0

		let newFilters = NodeFilterParameters(store: defaults)
		#expect(newFilters.hopsAway == 0.0)
	}

	@Test("Special characters in search text round-trip")
	func specialCharactersInSearchText() {
		let filters = NodeFilterParameters(store: defaults)
		filters.searchText = "Test!@#$%^&*()_+-=[]{}|;':\",./<>?"

		#expect(filters.searchText == "Test!@#$%^&*()_+-=[]{}|;':\",./<>?")
	}

	@Test("Unicode in search text round-trips")
	func unicodeInSearchText() {
		let filters = NodeFilterParameters(store: defaults)
		filters.searchText = "测试 Тест 🎉🚀"

		#expect(filters.searchText == "测试 Тест 🎉🚀")
	}

	@Test("Long search text round-trips")
	func longSearchText() {
		let filters = NodeFilterParameters(store: defaults)
		let longText = String(repeating: "A", count: 1000)
		filters.searchText = longText

		#expect(filters.searchText == longText)
	}

	@Test("Large device roles set persists")
	func largeDeviceRolesSet() {
		let filters = NodeFilterParameters(store: defaults)
		filters.deviceRoles = Set(0...100)

		let newFilters = NodeFilterParameters(store: defaults)
		#expect(newFilters.deviceRoles == Set(0...100))
		#expect(newFilters.deviceRoles.count == 101)
	}

	// MARK: - Reset/Clear Tests

	@Test("reset() restores defaults and clears persisted values")
	func resetAllFilters() {
		let filters = NodeFilterParameters(store: defaults)

		// Set all values to non-default
		filters.searchText = "Test"
		filters.isOnline = true
		filters.isPkiEncrypted = true
		filters.isFavorite = true
		filters.isIgnored = true
		filters.isEnvironment = true
		filters.distanceFilter = true
		filters.maxDistance = 500_000
		filters.hopsAway = 5.0
		filters.roleFilter = true
		filters.deviceRoles = [1, 2, 3]
		filters.viaLora = false

		filters.reset()

		// In-memory values are back to defaults
		#expect(filters.searchText == "")
		#expect(filters.isOnline == false)
		#expect(filters.isPkiEncrypted == false)
		#expect(filters.isFavorite == false)
		#expect(filters.isIgnored == false)
		#expect(filters.isEnvironment == false)
		#expect(filters.distanceFilter == false)
		#expect(filters.maxDistance == 800_000)
		#expect(filters.hopsAway == -1.0)
		#expect(filters.roleFilter == false)
		#expect(filters.deviceRoles.isEmpty)
		#expect(filters.viaLora == true)
		#expect(filters.viaMqtt == true)

		// reset() persists the defaults, so a fresh instance loads them too
		let newFilters = NodeFilterParameters(store: defaults)
		#expect(newFilters.isOnline == false)
		#expect(newFilters.isPkiEncrypted == false)
		#expect(newFilters.isFavorite == false)
		#expect(newFilters.isIgnored == false)
		#expect(newFilters.isEnvironment == false)
		#expect(newFilters.distanceFilter == false)
		#expect(newFilters.maxDistance == 800_000)
		#expect(newFilters.hopsAway == -1.0)
		#expect(newFilters.roleFilter == false)
		#expect(newFilters.deviceRoles.isEmpty)
		#expect(newFilters.viaLora == true)
		#expect(newFilters.viaMqtt == true)
	}
}

// MARK: - matches() Tests

/// Tests for `NodeFilterParameters.matches(_:)`, the in-memory filter-matching used by
/// `@Query` results. Because `NodeInfoEntity` is a SwiftData `@Model`, these tests build
/// entities inside an in-memory `ModelContainer` (the shared test container) so relationships
/// (`user`, `positions`) and computed accessors (`latestPosition`, `hasEnvironmentMetrics`)
/// behave as they do at runtime.
@MainActor
@Suite("NodeFilterParameters.matches", .serialized)
struct NodeFilterParametersMatchesTests {

	/// Isolated defaults store, injected into every `NodeFilterParameters` under test.
	let defaults: UserDefaults

	init() {
		// matches() reads no UserDefaults itself, but the filter flags it consults are
		// @AppStorage-backed, so each test gets an isolated, empty store.
		defaults = makeIsolatedDefaults("NodeFilterParametersTests.matches")
	}

	// MARK: Fixtures

	/// Inserts a bare node with a unique `num` into the context.
	@discardableResult
	private func makeNode(_ context: ModelContext, num: Int64) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		context.insert(node)
		return node
	}

	/// Attaches a `UserEntity` (carrying role / pki state) to a node.
	private func attachUser(
		_ context: ModelContext,
		to node: NodeInfoEntity,
		role: Int32 = 0,
		pkiEncrypted: Bool = false
	) {
		let user = UserEntity()
		user.num = node.num
		user.userId = "!\(String(node.num, radix: 16))"
		user.role = role
		user.pkiEncrypted = pkiEncrypted
		context.insert(user)
		node.user = user
	}

	// MARK: Online filter

	@Test("Online filter matches only recently-heard nodes")
	func onlineFilter() {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		filters.isOnline = true

		let reference = Date()
		let threshold = reference.addingTimeInterval(-7_200)

		let recent = makeNode(context, num: 9_910_001)
		recent.lastHeard = reference

		let stale = makeNode(context, num: 9_910_002)
		stale.lastHeard = reference.addingTimeInterval(-10_000)

		let neverHeard = makeNode(context, num: 9_910_003)
		neverHeard.lastHeard = nil

		#expect(filters.matches(recent, onlineThreshold: threshold))
		#expect(!filters.matches(stale, onlineThreshold: threshold))
		#expect(!filters.matches(neverHeard, onlineThreshold: threshold))
	}

	// MARK: Role filter

	@Test("Role filter matches only selected device roles")
	func roleFilter() {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		filters.roleFilter = true
		filters.deviceRoles = [2]

		let matchingRole = makeNode(context, num: 9_920_001)
		attachUser(context, to: matchingRole, role: 2)

		let otherRole = makeNode(context, num: 9_920_002)
		attachUser(context, to: otherRole, role: 1)

		let noUser = makeNode(context, num: 9_920_003)

		#expect(filters.matches(matchingRole))
		#expect(!filters.matches(otherRole))
		#expect(!filters.matches(noUser))
	}

	// MARK: Hops filter

	@Test("Hops filter set to zero matches only directly-connected nodes")
	func directHopsFilter() {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		filters.hopsAway = 0.0

		let direct = makeNode(context, num: 9_930_001) // hopsAway defaults to 0

		let remote = makeNode(context, num: 9_930_002)
		remote.hopsAway = 3

		#expect(filters.matches(direct))
		#expect(!filters.matches(remote))
	}

	@Test("Hops filter with a maximum matches nodes within range")
	func maxHopsFilter() {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		filters.hopsAway = 3.0

		let within = makeNode(context, num: 9_931_001)
		within.hopsAway = 2

		let direct = makeNode(context, num: 9_931_002)
		direct.hopsAway = 0 // hopsAway <= 0 is excluded when a positive max is set

		let tooFar = makeNode(context, num: 9_931_003)
		tooFar.hopsAway = 5

		#expect(filters.matches(within))
		#expect(!filters.matches(direct))
		#expect(!filters.matches(tooFar))
	}

	// MARK: Distance filter

	@Test("Distance filter matches nodes inside the bounds")
	func distanceFilter() throws {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		filters.distanceFilter = true

		let center = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let bounds = try #require(NodeDistanceFilterBounds(center: center, maxDistance: 10_000))

		let inside = PositionEntity()
		inside.latitudeI = 370_000_000   // 37.0
		inside.longitudeI = -1_220_000_000 // -122.0
		inside.latest = true

		let outside = PositionEntity()
		outside.latitudeI = 380_000_000  // 38.0, ~111 km north of center
		outside.longitudeI = -1_220_000_000
		outside.latest = true

		let nearNode = makeNode(context, num: 9_940_001)
		let farNode = makeNode(context, num: 9_940_002)
		let noPositionNode = makeNode(context, num: 9_940_003)

		#expect(filters.matches(nearNode, latestPosition: inside, distanceBounds: bounds))
		#expect(!filters.matches(farNode, latestPosition: outside, distanceBounds: bounds))
		#expect(!filters.matches(noPositionNode, distanceBounds: bounds))
	}

	@Test("Distance filter falls back to the node's latest position")
	func distanceFilterUsesNodeLatestPosition() throws {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		filters.distanceFilter = true

		let center = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let bounds = try #require(NodeDistanceFilterBounds(center: center, maxDistance: 10_000))

		let node = makeNode(context, num: 9_941_001)
		let position = PositionEntity()
		position.latitudeI = 370_000_000
		position.longitudeI = -1_220_000_000
		position.latest = true
		position.time = Date()
		position.nodePosition = node
		context.insert(position)
		node.latestPositionCache = position
		try context.save()

		#expect(filters.matches(node, distanceBounds: bounds))
	}

	// MARK: PKI filter

	@Test("PKI filter matches only PKI-encrypted nodes")
	func pkiFilter() {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		filters.isPkiEncrypted = true

		let encrypted = makeNode(context, num: 9_950_001)
		attachUser(context, to: encrypted, pkiEncrypted: true)

		let plain = makeNode(context, num: 9_950_002)
		attachUser(context, to: plain, pkiEncrypted: false)

		let noUser = makeNode(context, num: 9_950_003)

		#expect(filters.matches(encrypted))
		#expect(!filters.matches(plain))
		#expect(!filters.matches(noUser))
	}

	// MARK: Ignored filter

	@Test("Ignored filter matches only ignored nodes when enabled")
	func ignoredFilterEnabled() {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		filters.isIgnored = true

		let ignored = makeNode(context, num: 9_960_001)
		ignored.ignored = true

		let notIgnored = makeNode(context, num: 9_960_002)

		#expect(filters.matches(ignored))
		#expect(!filters.matches(notIgnored))
	}

	@Test("Ignored nodes are excluded when the filter is disabled")
	func ignoredExcludedByDefault() {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		// isIgnored defaults to false

		let ignored = makeNode(context, num: 9_961_001)
		ignored.ignored = true

		let notIgnored = makeNode(context, num: 9_961_002)

		#expect(!filters.matches(ignored))
		#expect(filters.matches(notIgnored))
	}

	// MARK: Environment filter

	@Test("Environment filter matches only nodes with environment telemetry")
	func environmentFilter() throws {
		let context = sharedModelContainer.mainContext
		let filters = NodeFilterParameters(store: defaults)
		filters.isEnvironment = true

		let withMetrics = makeNode(context, num: 9_970_001)
		let telemetry = TelemetryEntity()
		telemetry.metricsType = 1 // environment metrics
		telemetry.time = Date()
		telemetry.nodeTelemetry = withMetrics
		context.insert(telemetry)

		let withoutMetrics = makeNode(context, num: 9_970_002)
		try context.save()

		#expect(filters.matches(withMetrics))
		#expect(!filters.matches(withoutMetrics))
	}
}
