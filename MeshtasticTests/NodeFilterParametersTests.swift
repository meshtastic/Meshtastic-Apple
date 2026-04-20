//
//  NodeFilterParametersTests.swift
//  Meshtastic
//
//  Created on 3/16/26.
//

import Foundation
import XCTest

@testable import Meshtastic

@MainActor
class NodeFilterParametersTests: XCTestCase {
	
	// MARK: - Initialization Tests
	
	func testDefaultInitialization() async throws {
		// Clean up UserDefaults before test
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		
		XCTAssertEqual(filters.searchText, "")
		XCTAssertEqual(filters.isOnline, false)
		XCTAssertEqual(filters.isPkiEncrypted, false)
		XCTAssertEqual(filters.isFavorite, false)
		XCTAssertEqual(filters.isIgnored, false)
		XCTAssertEqual(filters.isEnvironment, false)
		XCTAssertEqual(filters.distanceFilter, false)
		XCTAssertEqual(filters.maxDistance, 800_000)
		XCTAssertEqual(filters.hopsAway, -1.0)
		XCTAssertEqual(filters.roleFilter, false)
		XCTAssertTrue(filters.deviceRoles.isEmpty)
		XCTAssertEqual(filters.viaLora, true)
		XCTAssertEqual(filters.viaMqtt, true)
	}
	
	func testInitializationWithPersistedDeviceRoles() async throws {
		clearAllFilterDefaults()
		
		// Store device roles in UserDefaults
		let expectedRoles = [1, 2, 3, 5, 8]
		UserDefaults.standard.set(expectedRoles, forKey: "nodeFilter.deviceRoles")
		
		let filters = NodeFilterParameters()
		
		XCTAssertEqual(filters.deviceRoles, Set(expectedRoles))
	}
	
	// MARK: - @AppStorage Persistence Tests
	
	func testSearchTextPersistence() async throws {
		clearAllFilterDefaults()
		
		let filters1 = NodeFilterParameters()
		filters1.searchText = "Test Node"
		
		let filters2 = NodeFilterParameters()
		XCTAssertEqual(filters2.searchText, "Test Node")
	}
	
	func testBooleanFiltersPersistence() async throws {
		clearAllFilterDefaults()
		
		let filters1 = NodeFilterParameters()
		filters1.isOnline = true
		filters1.isPkiEncrypted = true
		filters1.isFavorite = true
		filters1.isIgnored = true
		filters1.isEnvironment = true
		filters1.distanceFilter = true
		filters1.roleFilter = true
		
		let filters2 = NodeFilterParameters()
		XCTAssertEqual(filters2.isOnline, true)
		XCTAssertEqual(filters2.isPkiEncrypted, true)
		XCTAssertEqual(filters2.isFavorite, true)
		XCTAssertEqual(filters2.isIgnored, true)
		XCTAssertEqual(filters2.isEnvironment, true)
		XCTAssertEqual(filters2.distanceFilter, true)
		XCTAssertEqual(filters2.roleFilter, true)
	}
	
	func testNumericFiltersPersistence() async throws {
		clearAllFilterDefaults()
		
		let filters1 = NodeFilterParameters()
		filters1.maxDistance = 500_000
		filters1.hopsAway = 3.0
		
		let filters2 = NodeFilterParameters()
		XCTAssertEqual(filters2.maxDistance, 500_000)
		XCTAssertEqual(filters2.hopsAway, 3.0)
	}
	
	// MARK: - Device Roles Tests
	
	func testDeviceRolesPersistence() async throws {
		clearAllFilterDefaults()
		
		let filters1 = NodeFilterParameters()
		filters1.deviceRoles = [1, 3, 5, 7]
		
		// Verify it's stored in UserDefaults
		let storedRoles = UserDefaults.standard.array(forKey: "nodeFilter.deviceRoles") as? [Int]
		XCTAssertNotNil(storedRoles)
		XCTAssertEqual(Set(storedRoles!), Set([1, 3, 5, 7]))
		
		// Verify it persists to new instance
		let filters2 = NodeFilterParameters()
		XCTAssertEqual(filters2.deviceRoles, Set([1, 3, 5, 7]))
	}
	
	func testAddingDeviceRoles() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		filters.deviceRoles.insert(2)
		filters.deviceRoles.insert(4)
		filters.deviceRoles.insert(6)
		
		let newFilters = NodeFilterParameters()
		XCTAssertTrue(newFilters.deviceRoles.contains(2))
		XCTAssertTrue(newFilters.deviceRoles.contains(4))
		XCTAssertTrue(newFilters.deviceRoles.contains(6))
		XCTAssertEqual(newFilters.deviceRoles.count, 3)
	}
	
	func testRemovingDeviceRoles() async throws {
		clearAllFilterDefaults()
		
		let filters1 = NodeFilterParameters()
		filters1.deviceRoles = [1, 2, 3, 4, 5]
		
		filters1.deviceRoles.remove(2)
		filters1.deviceRoles.remove(4)
		
		let filters2 = NodeFilterParameters()
		XCTAssertEqual(filters2.deviceRoles, Set([1, 3, 5]))
		XCTAssertFalse(filters2.deviceRoles.contains(2))
		XCTAssertFalse(filters2.deviceRoles.contains(4))
	}
	
	func testEmptyDeviceRolesPersistence() async throws {
		clearAllFilterDefaults()
		
		let filters1 = NodeFilterParameters()
		filters1.deviceRoles = [1, 2, 3]
		
		// Clear the set
		filters1.deviceRoles = []
		
		let filters2 = NodeFilterParameters()
		XCTAssertTrue(filters2.deviceRoles.isEmpty)
	}
	
	// MARK: - Via Lora/MQTT Enforcement Tests
	
	func testViaLoraEnforcesViaMqtt() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		
		// Start with both true
		XCTAssertEqual(filters.viaLora, true)
		XCTAssertEqual(filters.viaMqtt, true)
		
		// Set viaLora to false
		filters.viaLora = false
		
		// viaMqtt should remain true
		XCTAssertEqual(filters.viaLora, false)
		XCTAssertEqual(filters.viaMqtt, true)
		
		// Try to set viaMqtt to false - it should enforce viaLora to true
		filters.viaMqtt = false
		
		XCTAssertEqual(filters.viaLora, true)
		XCTAssertEqual(filters.viaMqtt, false)
	}
	
	func testViaMqttEnforcesViaLora() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		
		// Start with both true
		XCTAssertEqual(filters.viaLora, true)
		XCTAssertEqual(filters.viaMqtt, true)
		
		// Set viaMqtt to false
		filters.viaMqtt = false
		
		// viaLora should remain true
		XCTAssertEqual(filters.viaLora, true)
		XCTAssertEqual(filters.viaMqtt, false)
		
		// Try to set viaLora to false - it should enforce viaMqtt to true
		filters.viaLora = false
		
		XCTAssertEqual(filters.viaLora, false)
		XCTAssertEqual(filters.viaMqtt, true)
	}
	
	func testBothViaTrue() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		filters.viaLora = true
		filters.viaMqtt = true
		
		XCTAssertEqual(filters.viaLora, true)
		XCTAssertEqual(filters.viaMqtt, true)
	}
	
	func testViaSettingsPersistence() async throws {
		clearAllFilterDefaults()
		
		let filters1 = NodeFilterParameters()
		filters1.viaLora = false
		// viaMqtt should be enforced to true
		
		let filters2 = NodeFilterParameters()
		XCTAssertEqual(filters2.viaLora, false)
		XCTAssertEqual(filters2.viaMqtt, true)
	}
	
	func testCannotHaveBothViaFalse() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		
		// Set viaLora to false first
		filters.viaLora = false
		XCTAssertEqual(filters.viaLora, false)
		XCTAssertEqual(filters.viaMqtt, true)
		
		// Try to set viaMqtt to false
		filters.viaMqtt = false
		
		// viaLora should be enforced back to true
		XCTAssertEqual(filters.viaLora, true)
		XCTAssertEqual(filters.viaMqtt, false)
	}
	
	// MARK: - ObservableObject Tests
	
	func testObjectWillChange() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
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
		XCTAssertGreaterThan(changeCount, 0)
		
		cancellable.cancel()
	}
	
	// MARK: - Edge Cases
	
	func testLargeMaxDistance() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		filters.maxDistance = 10_000_000
		
		let newFilters = NodeFilterParameters()
		XCTAssertEqual(newFilters.maxDistance, 10_000_000)
	}
	
	func testNegativeHopsAway() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		filters.hopsAway = -1.0
		
		let newFilters = NodeFilterParameters()
		XCTAssertEqual(newFilters.hopsAway, -1.0)
	}
	
	func testZeroHopsAway() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		filters.hopsAway = 0.0
		
		let newFilters = NodeFilterParameters()
		XCTAssertEqual(newFilters.hopsAway, 0.0)
	}
	
	func testSpecialCharactersInSearchText() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		filters.searchText = "Test!@#$%^&*()_+-=[]{}|;':\",./<>?"
		
		let newFilters = NodeFilterParameters()
		XCTAssertEqual(newFilters.searchText, "Test!@#$%^&*()_+-=[]{}|;':\",./<>?")
	}
	
	func testUnicodeInSearchText() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		filters.searchText = "测试 Тест 🎉🚀"
		
		let newFilters = NodeFilterParameters()
		XCTAssertEqual(newFilters.searchText, "测试 Тест 🎉🚀")
	}
	
	func testLongSearchText() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		let longText = String(repeating: "A", count: 1000)
		filters.searchText = longText
		
		let newFilters = NodeFilterParameters()
		XCTAssertEqual(newFilters.searchText, longText)
	}
	
	func testLargeDeviceRolesSet() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		filters.deviceRoles = Set(0...100)
		
		let newFilters = NodeFilterParameters()
		XCTAssertEqual(newFilters.deviceRoles, Set(0...100))
		XCTAssertEqual(newFilters.deviceRoles.count, 101)
	}
	
	// MARK: - Reset/Clear Tests
	
	func testResetAllFilters() async throws {
		clearAllFilterDefaults()
		
		let filters = NodeFilterParameters()
		
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
		
		// Reset to defaults
		filters.searchText = ""
		filters.isOnline = false
		filters.isPkiEncrypted = false
		filters.isFavorite = false
		filters.isIgnored = false
		filters.isEnvironment = false
		filters.distanceFilter = false
		filters.maxDistance = 800_000
		filters.hopsAway = -1.0
		filters.roleFilter = false
		filters.deviceRoles = []
		filters.viaLora = true
		filters.viaMqtt = true
		
		// Verify all are back to defaults
		let newFilters = NodeFilterParameters()
		XCTAssertEqual(newFilters.searchText, "")
		XCTAssertEqual(newFilters.isOnline, false)
		XCTAssertEqual(newFilters.isPkiEncrypted, false)
		XCTAssertEqual(newFilters.isFavorite, false)
		XCTAssertEqual(newFilters.isIgnored, false)
		XCTAssertEqual(newFilters.isEnvironment, false)
		XCTAssertEqual(newFilters.distanceFilter, false)
		XCTAssertEqual(newFilters.maxDistance, 800_000)
		XCTAssertEqual(newFilters.hopsAway, -1.0)
		XCTAssertEqual(newFilters.roleFilter, false)
		XCTAssertTrue(newFilters.deviceRoles.isEmpty)
		XCTAssertEqual(newFilters.viaLora, true)
		XCTAssertEqual(newFilters.viaMqtt, true)
	}
	
	// MARK: - Helper Functions
	
	/// Clears all NodeFilter-related UserDefaults to ensure clean test state
	private func clearAllFilterDefaults() {
		let defaults = UserDefaults.standard
		defaults.removeObject(forKey: "nodeFilter.searchText")
		defaults.removeObject(forKey: "nodeFilter.isOnline")
		defaults.removeObject(forKey: "nodeFilter.isPkiEncrypted")
		defaults.removeObject(forKey: "nodeFilter.isFavorite")
		defaults.removeObject(forKey: "nodeFilter.isIgnored")
		defaults.removeObject(forKey: "nodeFilter.isEnvironment")
		defaults.removeObject(forKey: "nodeFilter.distanceFilter")
		defaults.removeObject(forKey: "nodeFilter.maxDistance")
		defaults.removeObject(forKey: "nodeFilter.hopsAway")
		defaults.removeObject(forKey: "nodeFilter.roleFilter")
		defaults.removeObject(forKey: "nodeFilter.deviceRoles")
		defaults.removeObject(forKey: "nodeFilter.viaLora")
		defaults.removeObject(forKey: "nodeFilter.viaMqtt")
	}
}
