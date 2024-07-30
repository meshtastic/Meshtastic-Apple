import CoreLocation
import OSLog
import SwiftUI

// Shared state that manages the `CLLocationManager` and `CLBackgroundActivitySession`.
@MainActor
class LocationsHandler: ObservableObject {
	static let shared = LocationsHandler()  // Create a single, shared instance of the object.
	static let defaultLocation = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)

	private let manager: CLLocationManager

	private var background: CLBackgroundActivitySession?
	private var enableSmartPosition = UserDefaults.enableSmartPosition

	@Published
	var locationsArray = [CLLocation]()
	@Published
	var isStationary = false
	@Published
	var count = 0
	@Published
	var isRecording = false
	@Published
	var isRecordingPaused = false
	@Published
	var recordingStarted: Date?
	@Published
	var distanceTraveled = 0.0
	@Published
	var elevationGain = 0.0

	@Published
	var updatesStarted: Bool = UserDefaults.standard.bool(forKey: "liveUpdatesStarted") {
		didSet {
			UserDefaults.standard.set(updatesStarted, forKey: "liveUpdatesStarted")
		}
	}

	@Published
	var backgroundActivity: Bool = UserDefaults.standard.bool(forKey: "BGActivitySessionStarted") {
		didSet {
			backgroundActivity ? background = CLBackgroundActivitySession() : background?.invalidate()
			UserDefaults.standard.set(backgroundActivity, forKey: "BGActivitySessionStarted")
		}
	}

	private init() {
		self.manager = CLLocationManager()
		self.manager.allowsBackgroundLocationUpdates = true
	}

	func startLocationUpdates() {
		if self.manager.authorizationStatus == .notDetermined {
			self.manager.requestWhenInUseAuthorization()
		}

		Logger.services.info("📍 [App] Starting location updates")

		Task {
			do {
				updatesStarted = true

				let updates = CLLocationUpdate.liveUpdates(.default)

				for try await update in updates {
					guard self.updatesStarted else {
						break
					}

					if let loc = update.location {
						isStationary = update.isStationary

						var locationAdded: Bool

						locationAdded = addLocation(loc, smartPostion: enableSmartPosition)
						if !isRecording && locationAdded {
							count = 1
						}
						else if locationAdded && isRecording {
							count += 1
						}
					}
				}
			}
			catch {
				Logger.services.error("💥 [App] Could not start location updates: \(error.localizedDescription)")
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
				Logger.services.warning("📍 [App] Bad Location \(self.count, privacy: .public): Too Old \(age, privacy: .public) seconds ago \(location, privacy: .private)")
				return false
			}

			if location.horizontalAccuracy < 0 {
				Logger.services.warning("📍 [App] Bad Location \(self.count, privacy: .public): Horizontal Accuracy: \(location.horizontalAccuracy) \(location, privacy: .private)")
				return false
			}

			if location.horizontalAccuracy > 5 {
				Logger.services.warning("📍 [App] Bad Location \(self.count, privacy: .public): Horizontal Accuracy: \(location.horizontalAccuracy) \(location, privacy: .private)")
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
		}
		else {
			locationsArray = [location]
		}

		return true
	}
}
