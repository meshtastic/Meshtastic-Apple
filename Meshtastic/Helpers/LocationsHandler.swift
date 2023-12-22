//
//  LocationsHandler.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/4/23.
//

import SwiftUI
import CoreLocation


// Shared state that manages the `CLLocationManager` and `CLBackgroundActivitySession`.
@available(iOS 17.0, macOS 14.0, *)
@MainActor class LocationsHandler: ObservableObject {
	
	static let shared = LocationsHandler()  // Create a single, shared instance of the object.
	private let manager: CLLocationManager
	private var background: CLBackgroundActivitySession?
	var locationsArray: [CLLocation]
	var enableSmartPosition: Bool
	
	@Published var lastLocation = CLLocation()
	@Published var isStationary = false
	@Published var count = 0
	
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
	
	private init() {
		self.manager = CLLocationManager()  // Creating a location manager instance is safe to call here in `MainActor`.
		locationsArray = [CLLocation]()
		enableSmartPosition = true
	}
	
	func startLocationUpdates() {
		if self.manager.authorizationStatus == .notDetermined {
			self.manager.requestWhenInUseAuthorization()
		}
		print("Starting location updates")
		Task() {
			do {
				self.updatesStarted = true
				let updates = CLLocationUpdate.liveUpdates()
				for try await update in updates {
					if !self.updatesStarted { break }  // End location updates by breaking out of the loop.
					if let loc = update.location {
						self.lastLocation = loc
						self.isStationary = update.isStationary
						self.count += 1
						var locationAdded: Bool
						if enableSmartPosition {
							locationAdded = addLocation(loc)
						} else {
							locationsArray.append(loc)
							locationAdded = true
						}
						if !locationAdded {
							//print("Bad Location \(self.count): \(loc)")
						}
					}
				}
			} catch {
				print("Could not start location updates")
			}
			return
		}
	}
	
	func stopLocationUpdates() {
		print("Stopping location updates")
		self.updatesStarted = false
	}
	
	func addLocation(_ location: CLLocation) -> Bool {
		let age = -location.timestamp.timeIntervalSinceNow
		if age > 10 {
			print("Bad Location \(self.count): Too Old \(location)")
			return false
		}
		if location.horizontalAccuracy < 0 {
			print("Bad Location \(self.count): Horizontal Accuracy: \(location.horizontalAccuracy) \(location)")
			return false
		}
		if location.horizontalAccuracy > 100 {
			print("Bad Location \(self.count): Horizontal Accuracy: \(location.horizontalAccuracy) \(location)")
			return false
		}
		locationsArray.append(location)
		return true
	}
	
	static let DefaultLocation = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
	
	static var satsInView: Int {
		// If we have a position we have a sat
		var sats = 1
		if shared.lastLocation.verticalAccuracy > 0 {
			sats = 4
			if 0...5 ~= shared.lastLocation.horizontalAccuracy {
				sats = 12
			} else if 6...15 ~= shared.lastLocation.horizontalAccuracy {
				sats = 10
			} else if 16...30 ~= shared.lastLocation.horizontalAccuracy {
				sats = 9
			} else if 31...45 ~= shared.lastLocation.horizontalAccuracy {
				sats = 7
			} else if 46...60 ~= shared.lastLocation.horizontalAccuracy {
				sats = 5
			}
		} else if shared.lastLocation.verticalAccuracy < 0 && 60...300 ~= shared.lastLocation.horizontalAccuracy {
			sats = 3
		} else if shared.lastLocation.verticalAccuracy < 0 && shared.lastLocation.horizontalAccuracy > 300 {
			sats = 2
		}
		return sats
	}
}
