import CoreLocation
import SwiftData
import Testing
@testable import Meshtastic

private final class RecordingLocationManager: CLLocationManager {
	var authorizationStatusOverride: CLAuthorizationStatus = .authorizedAlways
	var requestAlwaysAuthorizationCallCount = 0
	var startUpdatingLocationCallCount = 0
	var stopUpdatingLocationCallCount = 0

	override var authorizationStatus: CLAuthorizationStatus {
		authorizationStatusOverride
	}

	override func requestAlwaysAuthorization() {
		requestAlwaysAuthorizationCallCount += 1
	}

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

@Suite("Location demand lifecycle", .serialized)
@MainActor
struct LocationDemandLifecycleTests {

	private func makeHandler() -> (LocationsHandler, RecordingLocationManager) {
		let manager = RecordingLocationManager()
		let handler = LocationsHandler(
			manager: manager,
			backgroundActivity: false,
			backgroundActivitySessionFactory: { nil }
		)
		return (handler, manager)
	}

	@Test func doesNotStartWithoutDemand() {
		let (_, manager) = makeHandler()

		#expect(manager.startUpdatingLocationCallCount == 0)
	}

	@Test func startsForFirstDemandAndStopsAfterLastDemand() {
		let (handler, manager) = makeHandler()

		handler.startLocationUpdates(for: .userInterface)
		handler.startLocationUpdates(for: .radioPositionSharing)
		handler.stopLocationUpdates(for: .userInterface)

		#expect(manager.startUpdatingLocationCallCount == 1)
		#expect(manager.stopUpdatingLocationCallCount == 0)

		handler.stopLocationUpdates(for: .radioPositionSharing)

		#expect(manager.stopUpdatingLocationCallCount == 1)
	}

	@Test func countsMultipleConsumersOfTheSamePurpose() {
		let (handler, manager) = makeHandler()

		handler.startLocationUpdates(for: .userInterface)
		handler.startLocationUpdates(for: .userInterface)
		handler.stopLocationUpdates(for: .userInterface)

		#expect(manager.stopUpdatingLocationCallCount == 0)

		handler.stopLocationUpdates(for: .userInterface)

		#expect(manager.stopUpdatingLocationCallCount == 1)
	}

	@Test func pausesForegroundDemandWhileApplicationIsInactive() {
		let (handler, manager) = makeHandler()
		handler.startLocationUpdates(for: .userInterface)

		handler.setApplicationActive(false)
		handler.setApplicationActive(true)

		#expect(manager.stopUpdatingLocationCallCount == 1)
		#expect(manager.startUpdatingLocationCallCount == 2)
	}

	@Test func routeRecordingKeepsBackgroundDeliveryActive() {
		let (handler, manager) = makeHandler()

		handler.isRecording = true
		handler.setApplicationActive(false)

		#expect(manager.startUpdatingLocationCallCount == 1)
		#expect(manager.stopUpdatingLocationCallCount == 0)
		#expect(manager.allowsBackgroundLocationUpdates)
		#expect(manager.desiredAccuracy == kCLLocationAccuracyBest)

		handler.isRecording = false

		#expect(manager.stopUpdatingLocationCallCount == 1)
		#expect(!manager.allowsBackgroundLocationUpdates)
		#expect(manager.desiredAccuracy == kCLLocationAccuracyHundredMeters)
	}

	@Test func startsPendingDemandAfterAuthorizationChanges() {
		let (handler, manager) = makeHandler()
		manager.authorizationStatusOverride = .notDetermined

		handler.startLocationUpdates(for: .userInterface)
		#expect(manager.startUpdatingLocationCallCount == 0)

		manager.authorizationStatusOverride = .authorizedWhenInUse
		handler.locationManagerDidChangeAuthorization(manager)

		#expect(manager.startUpdatingLocationCallCount == 1)
	}

	@Test func stopsDeliveryAfterAuthorizationIsRevoked() {
		let (handler, manager) = makeHandler()
		handler.startLocationUpdates(for: .userInterface)

		manager.authorizationStatusOverride = .denied
		handler.locationManagerDidChangeAuthorization(manager)

		#expect(manager.stopUpdatingLocationCallCount == 1)
	}

	@Test func waitsForFirstLocationAndReleasesDemand() async {
		let (handler, manager) = makeHandler()
		handler.enableSmartPosition = false
		let expected = CLLocation(latitude: 37.3346, longitude: -122.0090)
		let locationTask = Task { @MainActor in
			await handler.location(for: .watchSync, timeout: .seconds(1))
		}

		await Task.yield()
		#expect(manager.startUpdatingLocationCallCount == 1)
		handler.locationManager(manager, didUpdateLocations: [expected])

		let location = await locationTask.value
		#expect(location?.coordinate.latitude == expected.coordinate.latitude)
		#expect(location?.coordinate.longitude == expected.coordinate.longitude)
		#expect(manager.stopUpdatingLocationCallCount == 1)
		#expect(!manager.allowsBackgroundLocationUpdates)
	}

	@Test func releasesOneShotDemandAfterTimeout() async {
		let (handler, manager) = makeHandler()

		let location = await handler.location(for: .watchSync, timeout: .milliseconds(1))

		#expect(location == nil)
		#expect(manager.startUpdatingLocationCallCount == 1)
		#expect(manager.stopUpdatingLocationCallCount == 1)
		#expect(!manager.allowsBackgroundLocationUpdates)
	}

	@Test func permissionRequestCanRetryAfterTimeout() async {
		let manager = RecordingLocationManager()
		let handler = LocationsHandler(
			manager: manager,
			backgroundActivity: false,
			backgroundActivitySessionFactory: { nil },
			permissionRequestTimeout: .milliseconds(1)
		)

		_ = await handler.requestLocationAlwaysPermissions()
		_ = await handler.requestLocationAlwaysPermissions()

		#expect(manager.requestAlwaysAuthorizationCallCount == 2)
	}

	@Test func completedPermissionRequestCancelsItsTimeout() async {
		let manager = RecordingLocationManager()
		let handler = LocationsHandler(
			manager: manager,
			backgroundActivity: false,
			backgroundActivitySessionFactory: { nil },
			permissionRequestTimeout: .milliseconds(200)
		)
		let firstRequest = Task { @MainActor in
			await handler.requestLocationAlwaysPermissions()
		}
		await Task.yield()
		handler.locationManagerDidChangeAuthorization(manager)
		_ = await firstRequest.value

		try? await Task.sleep(for: .milliseconds(150))
		let secondRequest = Task { @MainActor in
			await handler.requestLocationAlwaysPermissions()
		}
		await Task.yield()
		try? await Task.sleep(for: .milliseconds(100))

		_ = await handler.requestLocationAlwaysPermissions()
		#expect(manager.requestAlwaysAuthorizationCallCount == 2)

		handler.locationManagerDidChangeAuthorization(manager)
		_ = await secondRequest.value
	}
}
