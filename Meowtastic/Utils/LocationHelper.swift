import CoreLocation
import Foundation
import MapKit
import OSLog

final class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
	static let shared = LocationHelper()
	static let defaultLocation = CLLocationCoordinate2D( // Apple Park
		latitude: 37.3346,
		longitude: -122.0090
	)
	static var currentLocation: CLLocationCoordinate2D {
		guard let location = shared.locationManager.location else {
			return defaultLocation
		}

		return location.coordinate
	}

	var locationManager = CLLocationManager()

	@Published
	var authorizationStatus: CLAuthorizationStatus?

	override init() {
		super.init()

		locationManager.delegate = self
		locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
		locationManager.pausesLocationUpdatesAutomatically = true
		locationManager.allowsBackgroundLocationUpdates = true
		locationManager.activityType = .other
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
		// no-op
	}

	func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
		// no-op
	}
}
