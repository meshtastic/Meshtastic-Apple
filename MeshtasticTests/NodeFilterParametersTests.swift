//
//  NodeFilterParametersTests.swift
//  MeshtasticTests
//
//  Created on 3/13/26.
//

import XCTest

@MainActor
final class NodeFilterParametersTests: XCTestCase {
	
	var sut: NodeFilterParameters!
	let testSuiteName = "NodeFilterParametersTests"
	
	override func setUp() async throws {
		try await super.setUp()
		
		// Clear UserDefaults before each test to ensure clean state
		clearUserDefaults()
		
		// Create a fresh instance
		sut = NodeFilterParameters()
	}
	
	override func tearDown() async throws {
		sut = nil
		clearUserDefaults()
		try await super.tearDown()
	}
		
	private func clearUserDefaults() {
		let defaults = UserDefaults.standard
		let keys = [
			"nodeFilter.searchText",
			"nodeFilter.isOnline",
			"nodeFilter.isPkiEncrypted",
			"nodeFilter.isFavorite",
			"nodeFilter.isIgnored",
			"nodeFilter.isEnvironment",
			"nodeFilter.distanceFilter",
			"nodeFilter.maxDistance",
			"nodeFilter.hopsAway",
			"nodeFilter.roleFilter",
			"nodeFilter.deviceRoles",
			"nodeFilter.viaLora",
			"nodeFilter.viaMqtt"
		]
		keys.forEach { defaults.removeObject(forKey: $0) }
	}
		
	func testDefaultValues() {
		XCTAssertEqual(sut.searchText, "", "Search text should default to empty string")
		XCTAssertFalse(sut.isOnline, "isOnline should default to false")
		XCTAssertFalse(sut.isPkiEncrypted, "isPkiEncrypted should default to false")
		XCTAssertFalse(sut.isFavorite, "isFavorite should default to false")
		XCTAssertFalse(sut.isIgnored, "isIgnored should default to false")
		XCTAssertFalse(sut.isEnvironment, "isEnvironment should default to false")
		XCTAssertFalse(sut.distanceFilter, "distanceFilter should default to false")
		XCTAssertEqual(sut.maxDistance, 800_000, "maxDistance should default to 800,000")
		XCTAssertEqual(sut.hopsAway, -1.0, "hopsAway should default to -1.0")
		XCTAssertFalse(sut.roleFilter, "roleFilter should default to false")
		XCTAssertTrue(sut.deviceRoles.isEmpty, "deviceRoles should default to empty set")
		XCTAssertTrue(sut.viaLora, "viaLora should default to true")
		XCTAssertTrue(sut.viaMqtt, "viaMqtt should default to true")
	}
		
	func testSearchTextPersistence() {
		sut.searchText = "Test Node"
		
		// Create new instance to test persistence
		let newInstance = NodeFilterParameters()
		XCTAssertEqual(newInstance.searchText, "Test Node", "Search text should persist")
	}
	
	func testBooleanFiltersPersistence() {
		sut.isOnline = true
		sut.isPkiEncrypted = true
		sut.isFavorite = true
		sut.isIgnored = true
		sut.isEnvironment = true
		
		let newInstance = NodeFilterParameters()
		XCTAssertTrue(newInstance.isOnline, "isOnline should persist")
		XCTAssertTrue(newInstance.isPkiEncrypted, "isPkiEncrypted should persist")
		XCTAssertTrue(newInstance.isFavorite, "isFavorite should persist")
		XCTAssertTrue(newInstance.isIgnored, "isIgnored should persist")
		XCTAssertTrue(newInstance.isEnvironment, "isEnvironment should persist")
	}
	
	func testDistanceFilterPersistence() {
		sut.distanceFilter = true
		sut.maxDistance = 50_000
		
		let newInstance = NodeFilterParameters()
		XCTAssertTrue(newInstance.distanceFilter, "distanceFilter should persist")
		XCTAssertEqual(newInstance.maxDistance, 50_000, "maxDistance should persist")
	}
	
	func testHopsAwayPersistence() {
		sut.hopsAway = 3.0
		
		let newInstance = NodeFilterParameters()
		XCTAssertEqual(newInstance.hopsAway, 3.0, "hopsAway should persist")
	}
	
	func testRoleFilterPersistence() {
		sut.roleFilter = true
		
		let newInstance = NodeFilterParameters()
		XCTAssertTrue(newInstance.roleFilter, "roleFilter should persist")
	}
		
	func testDeviceRolesInitiallyEmpty() {
		XCTAssertTrue(sut.deviceRoles.isEmpty, "deviceRoles should be empty initially")
	}
	
	func testDeviceRolesPersistence() {
		// Add some roles
		sut.deviceRoles = [0, 1, 2]
		
		// Verify they're stored in UserDefaults
		let stored = UserDefaults.standard.array(forKey: "nodeFilter.deviceRoles") as? [Int]
		XCTAssertNotNil(stored, "deviceRoles should be stored in UserDefaults")
		XCTAssertEqual(Set(stored ?? []), Set([0, 1, 2]), "Stored roles should match")
		
		// Create new instance to test persistence
		let newInstance = NodeFilterParameters()
		XCTAssertEqual(newInstance.deviceRoles, [0, 1, 2], "deviceRoles should persist")
	}
	
	func testDeviceRolesAddAndRemove() {
		XCTAssertTrue(sut.deviceRoles.isEmpty, "Should start empty")
		
		// Add roles
		sut.deviceRoles.insert(1)
		sut.deviceRoles.insert(3)
		sut.deviceRoles.insert(5)
		XCTAssertEqual(sut.deviceRoles.count, 3, "Should have 3 roles")
		
		// Remove a role
		sut.deviceRoles.remove(3)
		XCTAssertEqual(sut.deviceRoles.count, 2, "Should have 2 roles after removal")
		XCTAssertTrue(sut.deviceRoles.contains(1), "Should still contain role 1")
		XCTAssertTrue(sut.deviceRoles.contains(5), "Should still contain role 5")
		XCTAssertFalse(sut.deviceRoles.contains(3), "Should not contain removed role 3")
		
		// Verify persistence after changes
		let newInstance = NodeFilterParameters()
		XCTAssertEqual(newInstance.deviceRoles, sut.deviceRoles, "Changes should persist")
	}
		
	func testViaLoraAndMqttBothTrueByDefault() {
		XCTAssertTrue(sut.viaLora, "viaLora should default to true")
		XCTAssertTrue(sut.viaMqtt, "viaMqtt should default to true")
	}
	
	func testCanSetViaLoraToFalseWhenMqttIsTrue() {
		sut.viaLora = false
		
		XCTAssertFalse(sut.viaLora, "viaLora should be false")
		XCTAssertTrue(sut.viaMqtt, "viaMqtt should remain true")
	}
	
	func testCanSetViaMqttToFalseWhenLoraIsTrue() {
		sut.viaMqtt = false
		
		XCTAssertFalse(sut.viaMqtt, "viaMqtt should be false")
		XCTAssertTrue(sut.viaLora, "viaLora should remain true")
	}
	
	func testEnforcesAtLeastOneViaLoraOrMqtt_WhenSettingLoraFalse() {
		// First set MQTT to false
		sut.viaMqtt = false
		XCTAssertFalse(sut.viaMqtt, "viaMqtt should be false")
		XCTAssertTrue(sut.viaLora, "viaLora should be true")
		
		// Try to set LoRa to false - should enforce MQTT back to true
		sut.viaLora = false
		
		XCTAssertFalse(sut.viaLora, "viaLora should be false")
		XCTAssertTrue(sut.viaMqtt, "viaMqtt should be enforced to true")
	}
	
	func testEnforcesAtLeastOneViaLoraOrMqtt_WhenSettingMqttFalse() {
		// First set LoRa to false
		sut.viaLora = false
		XCTAssertFalse(sut.viaLora, "viaLora should be false")
		XCTAssertTrue(sut.viaMqtt, "viaMqtt should be true")
		
		// Try to set MQTT to false - should enforce LoRa back to true
		sut.viaMqtt = false
		
		XCTAssertFalse(sut.viaMqtt, "viaMqtt should be false")
		XCTAssertTrue(sut.viaLora, "viaLora should be enforced to true")
	}
	
	func testViaLoraAndMqttPersistence() {
		sut.viaLora = false
		sut.viaMqtt = true
		
		let newInstance = NodeFilterParameters()
		XCTAssertFalse(newInstance.viaLora, "viaLora state should persist")
		XCTAssertTrue(newInstance.viaMqtt, "viaMqtt state should persist")
	}
	
	// MARK: - ObservableObject Tests
	
	func testObjectWillChangeTriggeredOnViaLoraChange() {
		let expectation = XCTestExpectation(description: "objectWillChange should trigger")
		
		let cancellable = sut.objectWillChange.sink {
			expectation.fulfill()
		}
		
		sut.viaLora = false
		
		wait(for: [expectation], timeout: 0.1)
		cancellable.cancel()
	}
	
	func testObjectWillChangeTriggeredOnViaMqttChange() {
		let expectation = XCTestExpectation(description: "objectWillChange should trigger")
		
		let cancellable = sut.objectWillChange.sink {
			expectation.fulfill()
		}
		
		sut.viaMqtt = false
		
		wait(for: [expectation], timeout: 0.1)
		cancellable.cancel()
	}
	
	func testObjectWillChangeTriggeredOnDeviceRolesChange() {
		let expectation = XCTestExpectation(description: "objectWillChange should trigger")
		expectation.expectedFulfillmentCount = 1
		
		let cancellable = sut.objectWillChange.sink {
			expectation.fulfill()
		}
		
		sut.deviceRoles = [1, 2, 3]
		
		wait(for: [expectation], timeout: 0.1)
		cancellable.cancel()
	}
		
	func testMaxDistanceBoundaryValues() {
		sut.maxDistance = 0
		XCTAssertEqual(sut.maxDistance, 0, "Should handle zero distance")
		
		sut.maxDistance = Double.greatestFiniteMagnitude
		XCTAssertEqual(sut.maxDistance, Double.greatestFiniteMagnitude, "Should handle large distances")
	}
	
	func testHopsAwayBoundaryValues() {
		sut.hopsAway = -1.0
		XCTAssertEqual(sut.hopsAway, -1.0, "Should handle -1 (all hops)")
		
		sut.hopsAway = 0.0
		XCTAssertEqual(sut.hopsAway, 0.0, "Should handle 0 (direct)")
		
		sut.hopsAway = 7.0
		XCTAssertEqual(sut.hopsAway, 7.0, "Should handle maximum hops")
	}
	
	func testSearchTextWithSpecialCharacters() {
		let specialStrings = [
			"Test Node #1",
			"Node@123",
			"Node with spaces",
			"Node_with_underscores",
			"Node-with-dashes",
			"Node.with.dots",
			"🎯 Node with emoji"
		]
		
		for testString in specialStrings {
			sut.searchText = testString
			XCTAssertEqual(sut.searchText, testString, "Should handle: \(testString)")
		}
	}
	
	func testDeviceRolesWithDuplicates() {
		sut.deviceRoles = [1, 2, 3]
		sut.deviceRoles.insert(2) // Try to insert duplicate
		
		XCTAssertEqual(sut.deviceRoles.count, 3, "Set should not contain duplicates")
		XCTAssertTrue(sut.deviceRoles.contains(1), "Should contain 1")
		XCTAssertTrue(sut.deviceRoles.contains(2), "Should contain 2")
		XCTAssertTrue(sut.deviceRoles.contains(3), "Should contain 3")
	}
	
	func testMultipleFiltersActive() {
		sut.searchText = "Test"
		sut.isOnline = true
		sut.isFavorite = true
		sut.distanceFilter = true
		sut.maxDistance = 100_000
		sut.hopsAway = 2.0
		sut.roleFilter = true
		sut.deviceRoles = [0, 1]
		sut.viaLora = true
		sut.viaMqtt = false
		
		// Verify all settings
		XCTAssertEqual(sut.searchText, "Test")
		XCTAssertTrue(sut.isOnline)
		XCTAssertTrue(sut.isFavorite)
		XCTAssertTrue(sut.distanceFilter)
		XCTAssertEqual(sut.maxDistance, 100_000)
		XCTAssertEqual(sut.hopsAway, 2.0)
		XCTAssertTrue(sut.roleFilter)
		XCTAssertEqual(sut.deviceRoles, [0, 1])
		XCTAssertTrue(sut.viaLora)
		XCTAssertFalse(sut.viaMqtt)
		
		// Verify persistence
		let newInstance = NodeFilterParameters()
		XCTAssertEqual(newInstance.searchText, "Test")
		XCTAssertTrue(newInstance.isOnline)
		XCTAssertTrue(newInstance.isFavorite)
		XCTAssertTrue(newInstance.distanceFilter)
		XCTAssertEqual(newInstance.maxDistance, 100_000)
		XCTAssertEqual(newInstance.hopsAway, 2.0)
		XCTAssertTrue(newInstance.roleFilter)
		XCTAssertEqual(newInstance.deviceRoles, [0, 1])
		XCTAssertTrue(newInstance.viaLora)
		XCTAssertFalse(newInstance.viaMqtt)
	}
}
