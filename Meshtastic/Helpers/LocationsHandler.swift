//
//  LocationsHandler.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 12/4/23.
//

import SwiftUI
import CoreLocation
import OSLog

enum LocationUpdatePurpose: Hashable {
	case userInterface
	case routeRecording
	case radioPositionSharing
	case watchSync
	case continuousBackground

	var requiresBackgroundDelivery: Bool {
		self == .routeRecording || self == .watchSync || self == .continuousBackground
	}
}

@MainActor class LocationsHandler: NSObject, ObservableObject, CLLocationManagerDelegate {

	static let shared = LocationsHandler()
	let manager: CLLocationManager
	private let backgroundActivitySessionFactory: () -> CLBackgroundActivitySession?
	private let permissionRequestTimeout: Duration
	private var background: CLBackgroundActivitySession?
	private var locationDemandCounts: [LocationUpdatePurpose: Int] = [:]
	private var locationDeliveryStarted = false
	private var applicationIsActive = true
	var enableSmartPosition: Bool = UserDefaults.enableSmartPosition

	@Published var locationsArray: [CLLocation] = [CLLocation]()
	@Published var isStationary = false
	@Published var count = 0
	@Published var isRecording = false {
		didSet {
			guard isRecording != oldValue else { return }
			updateAccuracyForRecordingState()
			if isRecording {
				startLocationUpdates(for: .routeRecording)
			} else {
				stopLocationUpdates(for: .routeRecording)
			}
		}
	}
	@Published var isRecordingPaused = false
	@Published var recordingStarted: Date?
	@Published var distanceTraveled = 0.0
	@Published var elevationGain = 0.0
	@Published var heading: Double = 0.0
	@Published var headingUpdatesStarted: Bool = false
	@Published private(set) var updatesStarted = false

	@Published var backgroundActivity: Bool {
		didSet {
			guard backgroundActivity != oldValue else { return }
			UserDefaults.standard.set(backgroundActivity, forKey: "BGActivitySessionStarted")
			if backgroundActivity {
				startLocationUpdates(for: .continuousBackground)
			} else {
				stopLocationUpdates(for: .continuousBackground)
			}
		}
	}

	// The continuation we will use to asynchronously ask the user permission to track their location.
	// This is an Optional to ensure it can be nilled out after use.
	private var permissionContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
	private var permissionTimeoutTask: Task<Void, Never>?

	// A flag to prevent multiple concurrent permission requests
	private var isRequestingPermission = false

	/// Requests "Always" location authorization from the user.
	/// It includes a timeout so the request can be retried if no delegate callback arrives.
	func requestLocationAlwaysPermissions() async -> CLAuthorizationStatus {
		guard !isRequestingPermission else {
			Logger.services.debug("📍 [App] requestLocationAlwaysPermissions called while a request is already active. Returning current status.")
			return manager.authorizationStatus
		}
		isRequestingPermission = true

		let status = await withCheckedContinuation { continuation in
			permissionContinuation = continuation
			manager.requestAlwaysAuthorization()

			permissionTimeoutTask = Task { @MainActor in
				do {
					try await Task.sleep(for: permissionRequestTimeout)
				} catch {
					return
				}
				guard let continuation = permissionContinuation else { return }
				Logger.services.warning("📍 [App] Location permission request timed out.")
				continuation.resume(returning: .denied)
				permissionContinuation = nil
				permissionTimeoutTask = nil
			}
		}
		permissionTimeoutTask?.cancel()
		permissionTimeoutTask = nil
		isRequestingPermission = false
		permissionContinuation = nil
		return status
	}

	/// Delegate method called when the location authorization status changes.
	/// - Parameter manager: The CLLocationManager instance.
	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		if let continuation = permissionContinuation {
			continuation.resume(returning: manager.authorizationStatus)
			permissionContinuation = nil
			permissionTimeoutTask?.cancel()
			permissionTimeoutTask = nil
		} else {
			Logger.services.debug("📍 [App] Location authorization changed without an active permission request.")
		}
		reconcileLocationDelivery()
	}

	init(
		manager: CLLocationManager = CLLocationManager(),
		backgroundActivity: Bool = UserDefaults.standard.bool(forKey: "BGActivitySessionStarted"),
		backgroundActivitySessionFactory: @escaping () -> CLBackgroundActivitySession? = { CLBackgroundActivitySession() },
		permissionRequestTimeout: Duration = .seconds(5)
	) {
		self.manager = manager
		self.backgroundActivity = backgroundActivity
		self.backgroundActivitySessionFactory = backgroundActivitySessionFactory
		self.permissionRequestTimeout = permissionRequestTimeout
		super.init()
		self.manager.delegate = self
		self.manager.allowsBackgroundLocationUpdates = false
		self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
		self.manager.distanceFilter = 10
		if CLLocationManager.headingAvailable() {
			self.manager.headingFilter = 1
			self.manager.headingOrientation = .portrait
		}
		if backgroundActivity {
			startLocationUpdates(for: .continuousBackground)
		}
	}

	func startLocationUpdates(for purpose: LocationUpdatePurpose) {
		locationDemandCounts[purpose, default: 0] += 1
		reconcileLocationDelivery()
	}

	func stopLocationUpdates(for purpose: LocationUpdatePurpose) {
		guard let count = locationDemandCounts[purpose] else { return }
		if count == 1 {
			locationDemandCounts.removeValue(forKey: purpose)
		} else {
			locationDemandCounts[purpose] = count - 1
		}
		reconcileLocationDelivery()
	}

	func setApplicationActive(_ isActive: Bool) {
		guard applicationIsActive != isActive else { return }
		applicationIsActive = isActive
		reconcileLocationDelivery()
	}

	func location(for purpose: LocationUpdatePurpose, timeout: Duration = .seconds(10)) async -> CLLocation? {
		if let location = locationsArray.last {
			return location
		}

		startLocationUpdates(for: purpose)
		defer { stopLocationUpdates(for: purpose) }

		return await withTaskGroup(of: CLLocation?.self) { group in
			group.addTask { @MainActor [weak self] in
				guard let self else { return nil }
				for await locations in self.$locationsArray.values {
					guard !Task.isCancelled else { return nil }
					if let location = locations.last {
						return location
					}
				}
				return nil
			}
			group.addTask {
				try? await Task.sleep(for: timeout)
				return nil
			}

			let location = await group.next() ?? nil
			group.cancelAll()
			return location
		}
	}

	// New method to start heading updates
	func startHeadingUpdates() {
		guard CLLocationManager.headingAvailable() else {
			Logger.services.warning("📍 [App] Heading updates not available on this device.")
			return
		}

		guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
			Logger.services.warning("📍 [App] Cannot start heading updates: insufficient authorization status.")
			return
		}

		Logger.services.info("📍 [App] Starting heading updates")
		manager.startUpdatingHeading()
		headingUpdatesStarted = true
	}

	// New method to stop heading updates
	func stopHeadingUpdates() {
		Logger.services.info("🛑 [App] Stopping heading updates")
		manager.stopUpdatingHeading()
		headingUpdatesStarted = false
	}

	// Implement the CLLocationManagerDelegate method for heading updates
	func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
		// Update heading on the main thread
		Task { @MainActor in
			self.heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
		}
	}

	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		Task { @MainActor in
			guard self.updatesStarted else { return }
			for location in locations {
				self.recordLocation(location, isStationary: false)
			}
		}
	}

	private func reconcileLocationDelivery() {
		let hasBackgroundDemand = locationDemandCounts.contains { purpose, count in
			count > 0 && purpose.requiresBackgroundDelivery
		}
		let hasForegroundDemand = locationDemandCounts.contains { purpose, count in
			count > 0 && !purpose.requiresBackgroundDelivery
		}
		let status = manager.authorizationStatus
		let isAuthorized = status == .authorizedAlways || status == .authorizedWhenInUse
		updateBackgroundDelivery(hasBackgroundDemand && isAuthorized)

		let hasActiveDemand = hasBackgroundDemand || (applicationIsActive && hasForegroundDemand)
		guard hasActiveDemand && isAuthorized else {
			stopLocationDelivery()
			return
		}
		guard !locationDeliveryStarted else { return }

		Logger.services.info("📍 [App] Starting location updates")
		updatesStarted = true
		locationDeliveryStarted = true
		manager.startUpdatingLocation()
	}

	private func stopLocationDelivery() {
		guard locationDeliveryStarted else {
			updatesStarted = false
			return
		}
		Logger.services.info("🛑 [App] Stopping location updates")
		updatesStarted = false
		locationDeliveryStarted = false
		manager.stopUpdatingLocation()
	}

	private func updateBackgroundDelivery(_ isRequired: Bool) {
		manager.allowsBackgroundLocationUpdates = isRequired
		if isRequired {
			if background == nil {
				background = backgroundActivitySessionFactory()
			}
		} else {
			background?.invalidate()
			background = nil
		}
	}

	private func recordLocation(_ location: CLLocation, isStationary: Bool) {
		self.isStationary = isStationary
		let locationAdded = addLocation(location, smartPostion: enableSmartPosition)
		if !isRecording && locationAdded {
			self.count = 1
		} else if locationAdded && isRecording {
			self.count += 1
		}
	}

	/// Escalates to best accuracy during route recording; reverts to battery-friendly defaults otherwise.
	private func updateAccuracyForRecordingState() {
		if isRecording {
			manager.desiredAccuracy = kCLLocationAccuracyBest
			manager.distanceFilter = kCLDistanceFilterNone
		} else {
			manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
			manager.distanceFilter = 10
		}
	}

	/// Adds a location to the array and updates tracking metrics, applying smart position filters if enabled.
	/// - Parameters:
	///   - location: The `CLLocation` object to add.
	///   - smartPostion: A boolean indicating whether to apply smart position filtering.
	/// - Returns: `true` if the location was added, `false` if it was filtered out by smart position.
	func addLocation(_ location: CLLocation, smartPostion: Bool) -> Bool {
		if smartPostion {
			let age = -location.timestamp.timeIntervalSinceNow
			if age > 10 {
				Logger.services.info("📍 [App] Smart Position - Bad Location: Too Old \(age, privacy: .public) seconds ago \(location, privacy: .private(mask: .none))")
				return false
			}
			if location.horizontalAccuracy < 0 {
				Logger.services.info("📍 [App] Smart Position - Bad Location: Horizontal Accuracy: \(location.horizontalAccuracy) \(location, privacy: .private(mask: .none))")
				return false
			}
			// Consider adjusting this threshold based on your needs. 5 meters is quite strict.
			if location.horizontalAccuracy > 5 {
				Logger.services.info("📍 [App] Smart Position - Bad Location: Horizontal Accuracy: \(location.horizontalAccuracy) \(location, privacy: .private(mask: .none))")
				return false
			}
		}
		if isRecording {
			if let lastLocation = locationsArray.last {
				let distance = location.distance(from: lastLocation)
				let gain = location.altitude - lastLocation.altitude
				distanceTraveled += distance
				if gain > 0 {
					elevationGain += gain
				}
			}
			locationsArray.append(location)
		} else {
			// If not recording, only keep the latest location.
			locationsArray = [location]
		}
		return true
	}
	// Default location (Apple Park) used as a fallback.
	// nonisolated because it is never mutated
	nonisolated static let DefaultLocation = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
	/// Provides the current location, falling back to last known or a default if necessary.
	static var currentLocation: CLLocationCoordinate2D? {
		// Attempt to get the most recent location from the manager.
		if let location = shared.manager.location {
			return location.coordinate
		} else {
			return nil
		}
	}
	/// Returns the current location only when it is valid and precise enough
	/// for distance-based filtering (horizontal accuracy ≤ 100 m and not stale).
	static var currentPreciseLocation: CLLocationCoordinate2D? {
		guard let location = shared.manager.location else { return nil }
		// Reject invalid accuracy
		guard location.horizontalAccuracy >= 0,
			  location.horizontalAccuracy <= 100 else { return nil }
		// Reject stale locations (older than 10 minutes)
		guard location.timestamp.timeIntervalSinceNow > -600 else { return nil }
		return location.coordinate
	}
	/// Estimates the number of satellites in view based on horizontal and vertical accuracy.
	/// This is a heuristic and not a direct report of satellite count.
	static var satsInView: Int {
		var sats = 0
		if let newLocation = shared.locationsArray.last {
			sats = 1
			if newLocation.verticalAccuracy > 0 {
				sats = 4
				if 0...5 ~= newLocation.horizontalAccuracy {
					sats = 12
				} else if 6...15 ~= newLocation.horizontalAccuracy {
					sats = 10
				} else if 16...30 ~= newLocation.horizontalAccuracy {
					sats = 9
				} else if 31...45 ~= newLocation.horizontalAccuracy {
					sats = 7
				} else if 46...60 ~= newLocation.horizontalAccuracy {
					sats = 5
				}
			} else if newLocation.verticalAccuracy < 0 && 60...300 ~= newLocation.horizontalAccuracy {
				sats = 3
			} else if newLocation.verticalAccuracy < 0 && newLocation.horizontalAccuracy > 300 {
				sats = 2
			}
		}
		return sats
	}
}

@MainActor
private struct LocationUpdatesModifier: ViewModifier {
	let purpose: LocationUpdatePurpose
	let isEnabled: Bool
	@State private var isVisible = false
	@State private var isRequestingUpdates = false

	func body(content: Content) -> some View {
		content
			.onAppear {
				isVisible = true
				updateDemand()
			}
			.onDisappear {
				isVisible = false
				updateDemand()
			}
			.onChange(of: isEnabled) { _, _ in
				updateDemand()
			}
	}

	private func updateDemand() {
		let shouldRequestUpdates = isVisible && isEnabled
		guard shouldRequestUpdates != isRequestingUpdates else { return }
		isRequestingUpdates = shouldRequestUpdates
		if shouldRequestUpdates {
			LocationsHandler.shared.startLocationUpdates(for: purpose)
		} else {
			LocationsHandler.shared.stopLocationUpdates(for: purpose)
		}
	}
}

extension View {
	@MainActor
	func locationUpdates(for purpose: LocationUpdatePurpose, while isEnabled: Bool = true) -> some View {
		modifier(LocationUpdatesModifier(purpose: purpose, isEnabled: isEnabled))
	}
}
