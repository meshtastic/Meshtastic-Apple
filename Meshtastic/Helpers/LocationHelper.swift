import Foundation
import CoreLocation
import MapKit

class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
	static let shared = LocationHelper()
	var locationManager = CLLocationManager()
	
	//@Published var region = MKCoordinateRegion()
	@Published var authorizationStatus: CLAuthorizationStatus?
	override init() {
		super.init()
		locationManager.delegate = self
		locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
		locationManager.pausesLocationUpdatesAutomatically = true
		locationManager.allowsBackgroundLocationUpdates = true
		locationManager.activityType = .other
	}
	// Apple Park
	static let DefaultLocation = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
	static var currentLocation: CLLocationCoordinate2D {
		guard let location = shared.locationManager.location else {
			return DefaultLocation
		}
		return location.coordinate
	}
	static var satsInView: Int {
		// If we have a position we have a sat
		var sats = 1
		if shared.locationManager.location?.verticalAccuracy ?? 0 > 0 {
			sats = 4
			if 0...5 ~= shared.locationManager.location?.horizontalAccuracy ?? 0 {
				sats = 12
			} else if 6...15 ~= shared.locationManager.location?.horizontalAccuracy ?? 0 {
				sats = 10
			} else if 16...30 ~= shared.locationManager.location?.horizontalAccuracy ?? 0 {
				sats = 9
			} else if 31...45 ~= shared.locationManager.location?.horizontalAccuracy ?? 0 {
				sats = 7
			} else if 46...60 ~= shared.locationManager.location?.horizontalAccuracy ?? 0 {
				sats = 5
			}
		} else if shared.locationManager.location?.verticalAccuracy ?? 0 < 0 && 60...300 ~= shared.locationManager.location?.horizontalAccuracy ?? 0 {
			sats = 3
		} else if shared.locationManager.location?.verticalAccuracy ?? 0 < 0 && shared.locationManager.location?.horizontalAccuracy ?? 0 > 300 {
			sats = 2
		}
		return sats
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
		let chimeOnLocationUpdate = true
		//		locationManager.stopUpdatingLocation()
		//		locations.last.map {
		//				region = MKCoordinateRegion(
		//					center: $0.coordinate,
		//					span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)
		//				)
		//			}
		// Play a sound so it's easy to tell when a location update occurs while the app is in the background.
		if chimeOnLocationUpdate && !locations.isEmpty {
			//  setSessionActiveWithMixing(true) // Ducks the audio of other apps when playing the chime.
			//  playSound()
		}
		
		// Always process all of the provided locations. Don't assume the array only contains a single location.
		for location in locations {
			
			print("process a location")
			// displayNewBreadcrumbOnMap(location)
		}
	}
	func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		print("Location manager error: \(error.localizedDescription)")
	}
}
