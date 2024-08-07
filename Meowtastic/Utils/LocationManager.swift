import CoreLocation
import Foundation
import MapKit
import OSLog

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
	static let shared = LocationManager()
	static let defaultLocation = CLLocation( // Apple Park
		latitude: 37.3346,
		longitude: -122.0090
	)

	private let locationManager: CLLocationManager

	private(set) var lastKnownLocation: CLLocation?

	@Published
	private var authorizationStatus: CLAuthorizationStatus?

	override init() {
		locationManager = CLLocationManager()
		locationManager.desiredAccuracy = kCLLocationAccuracyBest
		locationManager.pausesLocationUpdatesAutomatically = false
		locationManager.allowsBackgroundLocationUpdates = true
		locationManager.activityType = .other

		super.init()

		locationManager.delegate = self
		locationManager.requestLocation()
	}

	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		switch manager.authorizationStatus {
		case .authorizedAlways:
			authorizationStatus = .authorizedAlways

		case .authorizedWhenInUse:
			authorizationStatus = .authorizedWhenInUse
			locationManager.requestLocation()

		case .restricted:
			authorizationStatus = .restricted

		case .denied:
			authorizationStatus = .denied

		case .notDetermined:
			authorizationStatus = .notDetermined
			locationManager.requestAlwaysAuthorization()

		default:
			break
		}
	}

	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		lastKnownLocation = locations.last

		if let coordinate = lastKnownLocation?.coordinate {
			MeshLogger.log("📍 We got new location: \(coordinate.latitude), \(coordinate.longitude)")
		}
	}

	func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
		// no-op
	}

	func getSafeLastKnownLocation() -> CLLocation {
		if let lastKnownLocation {
			return lastKnownLocation
		}

		return Self.defaultLocation
	}
}
