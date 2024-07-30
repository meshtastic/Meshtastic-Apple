import CoreLocation
import OSLog
import SwiftUI

// Shared state that manages the `CLLocationManager` and `CLBackgroundActivitySession`.
@MainActor
class LocationsHandler: ObservableObject {
	static let shared = LocationsHandler()  // Create a single, shared instance of the object.

	private let manager: CLLocationManager

	private var background: CLBackgroundActivitySession?
	private var enableSmartPosition = UserDefaults.enableSmartPosition

	@Published
	var locationsArray = [CLLocation]()
	@Published
	var count = 0

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
		if manager.authorizationStatus == .notDetermined {
			manager.requestWhenInUseAuthorization()
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
						var locationAdded: Bool

						locationAdded = addLocation(loc, smartPostion: enableSmartPosition)
						if locationAdded {
							count = 1
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

		updatesStarted = false
	}

	func addLocation(_ location: CLLocation, smartPostion: Bool) -> Bool {
		if smartPostion {
			let age = -location.timestamp.timeIntervalSinceNow
			if age > 10 || location.horizontalAccuracy < 0 || location.horizontalAccuracy > 5 {
				return false
			}
		}

		locationsArray = [location]

		return true
	}
}
