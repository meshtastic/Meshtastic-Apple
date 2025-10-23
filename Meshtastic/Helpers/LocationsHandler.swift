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
	private var background: AnyObject?
	var enableSmartPosition: Bool = UserDefaults.enableSmartPosition

	@Published var locationsArray: [CLLocation] = [CLLocation]()
	@Published var isStationary = false
	@Published var count = 0
	@Published var isRecording = false
	@Published var isRecordingPaused = false
	@Published var recordingStarted: Date?
	@Published var distanceTraveled = 0.0
	@Published var elevationGain = 0.0

	private var liveUpdatesTask: Task<Void, Never>?

	@Published
	var updatesStarted: Bool = UserDefaults.standard.bool(forKey: "liveUpdatesStarted") {
		didSet { UserDefaults.standard.set(updatesStarted, forKey: "liveUpdatesStarted") }
	}

	@Published
	var backgroundActivity: Bool = UserDefaults.standard.bool(forKey: "BGActivitySessionStarted") {
		didSet {
			updateBackgroundActivitySession()
			UserDefaults.standard.set(backgroundActivity, forKey: "BGActivitySessionStarted")
		}
	}

	// The continuation we will use to asynchronously ask the user permission to track their location.
	// This is an Optional to ensure it can be nilled out after use.
	private var permissionContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

	// A flag to prevent multiple concurrent permission requests
	private var isRequestingPermission = false

	/// Requests "Always" location authorization from the user.
	/// This method uses Swift's structured concurrency to await the user's decision.
	/// It includes a timeout to prevent continuation leaks if the delegate method isn't called.
	/// - Returns: The `CLAuthorizationStatus` reflecting the user's choice.
	func requestLocationAlwaysPermissions() async -> CLAuthorizationStatus {
		// If a request is already in progress, return the current status immediately.
		// This prevents creating multiple continuations and potential leaks.
		guard !isRequestingPermission else {
			Logger.services.debug("📍 [App] requestLocationAlwaysPermissions called while a request is already active. Returning current status.")
			return manager.authorizationStatus
		}
		// Set flag to indicate a request is in progress
		isRequestingPermission = true

		return await withCheckedContinuation { continuation in
			// Store the continuation.
			self.permissionContinuation = continuation

			// Request authorization. The response will come via `locationManagerDidChangeAuthorization`.
			manager.requestAlwaysAuthorization()

			// Add a timeout to ensure the continuation is always resumed.
			// If the delegate method doesn't fire within a reasonable time (e.g., 10 seconds),
			// we'll resume the continuation with .notDetermined to prevent a leak.
			Task { @MainActor in // Ensure this task runs on the MainActor
				do {
					try await Task.sleep(nanoseconds: 5_000_000_000) // Wait for 5 seconds
					if let currentContinuation = self.permissionContinuation {
						// If the continuation hasn't been nilled out yet, it means
						// locationManagerDidChangeAuthorization hasn't been called.
						Logger.services.warning("📍 [App] Location permission request timed out. Resuming continuation with .notDetermined.")
						currentContinuation.resume(returning: .denied)
						self.permissionContinuation = nil // Clear the reference
					}
				} catch is CancellationError {
					// This task was cancelled, likely because the main continuation was already resumed
					// by locationManagerDidChangeAuthorization. This is expected and safe.
					Logger.services.debug("📍 [App] Permission timeout task cancelled.")
				} catch {
					Logger.services.error("💥 [App] Error in permission timeout task: \(error.localizedDescription, privacy: .public)")
				}
			}
		}
		// This defer block ensures `isRequestingPermission` is reset and `permissionContinuation` is nilled out
		// regardless of how the `withCheckedContinuation` block exits (success, error, or cancellation).
		// It acts as a final cleanup mechanism.
		defer {
			self.isRequestingPermission = false
			// This nil assignment is somewhat redundant with the one in locationManagerDidChangeAuthorization
			// and the timeout Task, but it provides an extra layer of safety.
			self.permissionContinuation = nil
		}
	}

	/// Delegate method called when the location authorization status changes.
	/// - Parameter manager: The CLLocationManager instance.
	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		// Ensure the continuation exists before attempting to resume it.
		// If it's nil, it means either no request was pending or it was already resumed (e.g., by the timeout).
		guard let continuation = permissionContinuation else {
			Logger.services.debug("📍 [App] locationManagerDidChangeAuthorization called but no permissionContinuation is active or it was already handled.")
			return
		}
		// Resume the continuation with the current authorization status.
		continuation.resume(returning: manager.authorizationStatus)
		// CRUCIAL: Nil out the continuation immediately after resuming it.
		// This prevents attempting to resume the same continuation multiple times,
		// which would lead to a runtime crash.
		self.permissionContinuation = nil
		self.isRequestingPermission = false // Reset the flag as the request has completed
	}

	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		guard updatesStarted, let location = locations.last else { return }
		handleLocationUpdate(location, isStationary: false)
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
		self.updatesStarted = true
		if #available(iOS 17.0, *) {
			liveUpdatesTask?.cancel()
			liveUpdatesTask = Task { @MainActor in
				do {
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
							let stationary: Bool
							if #available(iOS 18.0, *) {
								stationary = update.stationary
							} else {
								stationary = false
							}
							self.handleLocationUpdate(loc, isStationary: stationary)
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
				liveUpdatesTask = nil
			}
		} else {
			manager.startUpdatingLocation()
		}
	}
	/// Stops receiving live location updates.
	func stopLocationUpdates() {
		Logger.services.info("🛑 [App] Stopping location updates")
		// Setting `updatesStarted` to false will cause the `liveUpdates()` loop to break.
		self.updatesStarted = false
		if #available(iOS 17.0, *) {
			liveUpdatesTask?.cancel()
			liveUpdatesTask = nil
		} else {
			manager.stopUpdatingLocation()
		}
	}

	private func updateBackgroundActivitySession() {
		if backgroundActivity {
			startBackgroundActivitySession()
		} else {
			stopBackgroundActivitySession()
		}
	}

	private func startBackgroundActivitySession() {
		stopBackgroundActivitySession()
		background = manager.startBackgroundActivitySessionCompat()
	}

	private func stopBackgroundActivitySession() {
		manager.invalidateBackgroundActivitySessionCompat(background)
		background = nil
	}
	private func handleLocationUpdate(_ location: CLLocation, isStationary: Bool) {
		self.isStationary = isStationary
		let locationAdded = addLocation(location, smartPostion: enableSmartPosition)
		if !isRecording && locationAdded {
			self.count = 1
		} else if locationAdded && isRecording {
			self.count += 1
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
