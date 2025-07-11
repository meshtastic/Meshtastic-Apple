//
//  LocationsHandler.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/4/23.
//

import SwiftUI
import CoreLocation
import OSLog

// Shared state that manages the `CLLocationManager` and `CLBackgroundActivitySession`.
@MainActor class LocationsHandler: ObservableObject {

	static let shared = LocationsHandler()  // Create a single, shared instance of the object.
	public let manager: CLLocationManager
	private var background: CLBackgroundActivitySession?
	var enableSmartPosition: Bool = UserDefaults.enableSmartPosition

	@Published var locationsArray: [CLLocation]
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
			backgroundActivity ? self.background = CLBackgroundActivitySession() : self.background?.invalidate()
			UserDefaults.standard.set(backgroundActivity, forKey: "BGActivitySessionStarted")
		}
	}
	
	// The continuation we will use to asynchronously ask the user permission to track their location.
	private var permissionContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

	func requestLocationAlwaysPermissions() async -> CLAuthorizationStatus {
		self.manager.requestAlwaysAuthorization()
		return await withCheckedContinuation { continuation in
		   permissionContinuation = continuation
		}
	}

	private init() {
		self.manager = CLLocationManager()  // Creating a location manager instance is safe to call here in `MainActor`.
		self.manager.allowsBackgroundLocationUpdates = true
		locationsArray = [CLLocation]()
	}

	func startLocationUpdates() {
		if self.manager.authorizationStatus == .notDetermined {
		//	self.manager.requestWhenInUseAuthorization()
		}
		let status = self.manager.authorizationStatus
		guard status == .authorizedAlways || status == .authorizedWhenInUse else {
			return
		}
		Logger.services.info("📍 [App] Starting location updates")
		Task {
			do {
				self.updatesStarted = true
				let updates = CLLocationUpdate.liveUpdates()
				for try await update in updates {
					if !self.updatesStarted { break }
					if let loc = update.location {
						self.isStationary = update.isStationary

						var locationAdded: Bool
						locationAdded = addLocation(loc, smartPostion: enableSmartPosition)
						if !isRecording && locationAdded {
							self.count = 1
						} else if locationAdded && isRecording {
							self.count += 1
						}
					}
				}
			} catch {
				Logger.services.error("💥 [App] Could not start location updates: \(error.localizedDescription, privacy: .public)")
			}
			return
		}
	}

	func stopLocationUpdates() {
		Logger.services.info("🛑 [App] Stopping location updates")
		self.updatesStarted = false
	}

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
			locationsArray = [location]
		}
		UserDefaults.standard.set(location.coordinate.latitude, forKey: "lastKnownLatitude")
		UserDefaults.standard.set(location.coordinate.longitude, forKey: "lastKnownLongitude")
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastKnownLocationTimestamp")
		return true
	}
	static let DefaultLocation = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
	static var currentLocation: CLLocationCoordinate2D {
		if let location = shared.manager.location {
			return location.coordinate
		} else {
			// Check authorization status
			let status = shared.manager.authorizationStatus
			switch status {
			case .notDetermined:
				Logger.services.info("📍 [App] Location permission not determined, requesting authorization")
				shared.manager.requestWhenInUseAuthorization()
			case .denied, .restricted:
				Logger.services.warning("📍 [App] Location access denied or restricted. Please enable location services in Settings to get accurate positioning!")
				shared.manager.requestWhenInUseAuthorization()
			default:
				break
			}
			// Fallback 1: Last known location from UserDefaults (if within 4 hours)
			if let lat = UserDefaults.standard.object(forKey: "lastKnownLatitude") as? Double,
				let lon = UserDefaults.standard.object(forKey: "lastKnownLongitude") as? Double,
				 let timestamp = UserDefaults.standard.object(forKey: "lastKnownLocationTimestamp") as? Double,
				 lat >= -90 && lat <= 90,
				 lon >= -180 && lon <= 180,
			   Date().timeIntervalSince1970 - timestamp <= 14_400 { // 4 hours in seconds
				Logger.services.info("📍 [App] Falling back to last known location (age: \(Int(Date().timeIntervalSince1970 - timestamp)) seconds)")
				return CLLocationCoordinate2D(latitude: lat, longitude: lon)
			}
			// Fallback 2: Default location
			Logger.services.warning("📍 [App] No Location and no last known location, something is really wrong. Teleporting user to Apple Park")
			return DefaultLocation
		}
	}

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
