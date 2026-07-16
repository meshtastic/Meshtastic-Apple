import CoreLocation
import SwiftData
import Testing
@testable import Meshtastic

private final class RecordingLocationManager: CLLocationManager {
	var startUpdatingLocationCallCount = 0
	var stopUpdatingLocationCallCount = 0

	override func startUpdatingLocation() {
		startUpdatingLocationCallCount += 1
	}

	override func stopUpdatingLocation() {
		stopUpdatingLocationCallCount += 1
	}
}

@Suite("Watch node serialization", .serialized)
struct WatchNodeSerializationTests {

	@MainActor
	@Test func usesCachedLatestPosition() throws {
		let context = sharedModelContainer.mainContext
		let nodeNum: Int64 = 2_001_003

		let node = NodeInfoEntity()
		node.num = nodeNum
		node.snr = 4.25
		node.lastHeard = Date(timeIntervalSince1970: 1_750_000_000)

		let user = UserEntity()
		user.num = nodeNum
		user.longName = "Cached Node"
		user.shortName = "CN"
		node.user = user

		let cached = PositionEntity()
		cached.latitudeI = 371234567
		cached.longitudeI = -1221234567
		cached.altitude = 42
		cached.time = Date(timeIntervalSince1970: 1_750_000_100)
		cached.nodePosition = node
		node.latestPositionCache = cached

		let staleLatest = PositionEntity()
		staleLatest.latitudeI = 376543210
		staleLatest.longitudeI = -1226543210
		staleLatest.altitude = 99
		staleLatest.latest = true
		staleLatest.time = Date(timeIntervalSince1970: 1_750_000_200)
		staleLatest.nodePosition = node

		context.insert(node)
		context.insert(user)
		context.insert(cached)
		context.insert(staleLatest)
		try context.save()

		let userLocation = CLLocation(latitude: 37.12345, longitude: -122.12345)
		let watchNode = WatchNode.make(from: node, userLocation: userLocation, maxDistanceMeters: 2_000)

		#expect(watchNode?.latitude == Double(cached.latitudeI) / 1e7)
		#expect(watchNode?.longitude == Double(cached.longitudeI) / 1e7)
		#expect(watchNode?.altitude == cached.altitude)
		#expect(watchNode?.longName == "Cached Node")
		#expect(watchNode?.shortName == "CN")
		#expect(watchNode?.snr == 4.25)
	}
}

@Suite("Location provider cadence")
struct LocationProviderCadenceTests {

	@Test func sleepIntervalUsesConfiguredIntervalWhenLongerThanMinimum() {
		#expect(AccessoryManager.locationProviderSleepSeconds(configuredInterval: 300) == 300)
	}

	@Test func sleepIntervalKeepsASaneMinimum() {
		#expect(AccessoryManager.locationProviderSleepSeconds(configuredInterval: 0) == 5)
		#expect(AccessoryManager.locationProviderSleepSeconds(configuredInterval: 3) == 5)
	}
}

@Suite("Location updates energy")
@MainActor
struct LocationUpdatesEnergyTests {

	@Test func beginsStandardLocationManagerUpdates() {
		let handler = LocationsHandler()
		let manager = RecordingLocationManager()
		handler.manager = manager

		handler.beginLocationDelivery()

		#expect(manager.startUpdatingLocationCallCount == 1)
	}

	@Test func endsStandardLocationManagerUpdates() {
		let handler = LocationsHandler()
		let manager = RecordingLocationManager()
		handler.manager = manager

		handler.stopLocationUpdates()

		#expect(manager.stopUpdatingLocationCallCount == 1)
	}
}
