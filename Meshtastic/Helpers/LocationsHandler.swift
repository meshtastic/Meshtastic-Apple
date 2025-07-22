//
//  LocationsHandler.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 12/4/23.
//

import SwiftUI
import CoreLocation
import OSLog

// The @MainActor annotation ensures that all state changes and UI updates happen on the main thread,
// preventing potential race conditions and crashes related to UI updates from background threads.
@MainActor class LocationsHandler: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {

	static let shared = LocationsHandler()  // Create a single, shared instance of the object.
	public var manager = CLLocationManager()
	private var background: CLBackgroundActivitySession?
	var enableSmartPosition: Bool = UserDefaults.enableSmartPosition

	@Published var locationsArray: [CLLocation] = [CLLocation]()
	@Published var isStationary = false
	@Published var count = 0
	@Published var isRecording = false
	@Published var isRecordingPaused = false
	@Published var recordingStarted: Date?
	@Published var distanceTraveled = 0.0
	@Published var elevationGain = 0.0

	@Published
	var updatesStarted: Bool = UserDefaults.standard.bool(forKey: "liveUpdatesStarted") {
		didSet { UserDefaults.standard.set(updatesStarted, forKey: "liveUpdatesStarted") }
	}

	@Published
	var backgroundActivity: Bool = UserDefaults.standard.bool(forKey: "BGActivitySessionStarted") {
		didSet {
			// Invalidate or create the background activity session based on the new value.
			backgroundActivity ? self.background = CLBackgroundActivitySession() : self.background?.invalidate()
			UserDefaults.standard.set(backgroundActivity, forKey: "BGActivitySessionStarted")
		}
	}
	// The continuation we will use to asynchronously ask the user permission to track their location.
	// This is an Optional to ensure it can be nilled out after use.
	private var permissionContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
	/// Requests "Always" location authorization from the user.
	/// This method uses Swift's structured concurrency to await the user's decision.
	/// - Returns: The `CLAuthorizationStatus` reflecting the user's choice.
	func requestLocationAlwaysPermissions() async -> CLAuthorizationStatus {
		return await withCheckedContinuation { continuation in
			// Store the continuation.
			self.permissionContinuation = continuation
			// Request authorization. The response will come via `locationManagerDidChangeAuthorization`.
			manager.requestAlwaysAuthorization()
		}
	}
	/// Delegate method called when the location authorization status changes.
	/// - Parameter manager: The CLLocationManager instance.
	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		// Ensure the continuation exists before attempting to resume it.
		// If it's nil, it means either no request was pending or it was already resumed.
		guard let continuation = permissionContinuation else {
			Logger.services.debug("📍 [App] locationManagerDidChangeAuthorization called but no permissionContinuation is active.")
			return
		}
		// Resume the continuation with the current authorization status.
		continuation.resume(returning: manager.authorizationStatus)
		// CRUCIAL: Nil out the continuation immediately after resuming it.
		// This prevents attempting to resume the same continuation multiple times,
		// which would lead to a runtime crash.
		self.permissionContinuation = nil
	}
	override init() {
		super.init()
		self.manager.delegate = self
		// Allow background location updates for continuous tracking.
		self.manager.allowsBackgroundLocationUpdates = true
		// Set desired accuracy for location updates.
		// Consider your app's needs: kCLLocationAccuracyBestForNavigation, kCLLocationAccuracyBest, etc.
		// For general tracking, kCLLocationAccuracyHundredMeters might be sufficient to save battery.
		self.manager.desiredAccuracy = kCLLocationAccuracyBest
		// Set the distance filter to only receive updates when the device has moved a certain distance.
		self.manager.distanceFilter = kCLDistanceFilterNone // Receive all updates initially
	}

	func startLocationUpdates() {
		let status = self.manager.authorizationStatus
		// Guard against starting updates without proper authorization.
		guard status == .authorizedAlways || status == .authorizedWhenInUse else {
			Logger.services.warning("📍 [App] Cannot start location updates: insufficient authorization status: \(status.rawValue)")
			return
		}
		Logger.services.info("📍 [App] Starting location updates")
		// Using a Task for asynchronous operations. The @MainActor isolation of the class
		// ensures that all state changes within this Task (accessing @Published properties)
		// will be performed on the main actor.
		Task { @MainActor in
			do {
				self.updatesStarted = true
				// `liveUpdates()` provides a stream of location updates.
				let updates = CLLocationUpdate.liveUpdates()
				for try await update in updates {
					// Check for task cancellation to allow graceful stopping.
					try Task.checkCancellation()
					// If `updatesStarted` is set to false (e.g., by `stopLocationUpdates`),
					// break out of the loop to stop processing updates.
					if !self.updatesStarted {
						Logger.services.info("🛑 [App] Location updates loop stopped due to updatesStarted being false.")
						break
					}
					if let loc = update.location {
						self.isStationary = update.isStationary
						let locationAdded = addLocation(loc, smartPostion: enableSmartPosition)
						if !isRecording && locationAdded {
							self.count = 1
						} else if locationAdded && isRecording {
							self.count += 1
						}
					}
				}
			} catch is CancellationError {
				// Handle explicit task cancellation gracefully.
				Logger.services.info("📍 [App] Location updates task was cancelled.")
			} catch {
				// Catch any other errors during location updates.
				Logger.services.error("💥 [App] Could not start location updates: \(error.localizedDescription, privacy: .public)")
			}
			// The Task completes implicitly here.
		}
	}
	/// Stops receiving live location updates.
	func stopLocationUpdates() {
		Logger.services.info("🛑 [App] Stopping location updates")
		// Setting `updatesStarted` to false will cause the `liveUpdates()` loop to break.
		self.updatesStarted = false
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
		// Store the last known location in UserDefaults for persistence.
		UserDefaults.standard.set(location.coordinate.latitude, forKey: "lastKnownLatitude")
		UserDefaults.standard.set(location.coordinate.longitude, forKey: "lastKnownLongitude")
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastKnownLocationTimestamp")
		return true
	}
	// Default location (Apple Park) used as a fallback.
	// nonisolated because it is never mutated
	nonisolated static let DefaultLocation = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
	/// Provides the current location, falling back to last known or a default if necessary.
	static var currentLocation: CLLocationCoordinate2D {
		// Attempt to get the most recent location from the manager.
		if let location = shared.manager.location {
			return location.coordinate
		} else {
			// If manager.location is nil, check authorization status and potentially request.
			let status = shared.manager.authorizationStatus
			switch status {
			case .notDetermined:
				Logger.services.info("📍 [App] Location permission not determined, requesting authorization (WhenInUse)")
				// Requesting WhenInUse authorization here. For "Always" authorization,
				// `requestLocationAlwaysPermissions()` should be called explicitly,
				// typically from a user action or app setup.
				shared.manager.requestWhenInUseAuthorization()
			case .denied, .restricted:
				Logger.services.warning("📍 [App] Location access denied or restricted. Please enable location services in Settings to get accurate positioning!")
				// Requesting WhenInUse authorization again, though user interaction is needed for denied/restricted.
				shared.manager.requestWhenInUseAuthorization()
			default:
				break // For .authorizedAlways, .authorizedWhenInUse, .limited
			}
			// Fallback 1: Last known location from UserDefaults if it's recent (within 4 hours).
			if let lat = UserDefaults.standard.object(forKey: "lastKnownLatitude") as? Double,
			   let lon = UserDefaults.standard.object(forKey: "lastKnownLongitude") as? Double,
			   let timestamp = UserDefaults.standard.object(forKey: "lastKnownLocationTimestamp") as? Double,
			   lat >= -90 && lat <= 90, // Validate latitude
			   lon >= -180 && lon <= 180, // Validate longitude
			   Date().timeIntervalSince1970 - timestamp <= 14_400 { // 4 hours in seconds
				Logger.services.info("📍 [App] Falling back to last known location (age: \(Int(Date().timeIntervalSince1970 - timestamp)) seconds)")
				return CLLocationCoordinate2D(latitude: lat, longitude: lon)
			}
			// Fallback 2: Default location if no other location is available.
			Logger.services.warning("📍 [App] No Location and no last known location, something is really wrong. Teleporting user to Apple Park")
			return DefaultLocation
		}
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
