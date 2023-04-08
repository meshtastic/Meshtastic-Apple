import CoreLocation

class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {

	private let locationManager = CLLocationManager()
    static let shared = LocationHelper()
	@Published var lastLocation: CLLocation?
	
	override init() {

		super.init()
		locationManager.delegate = self
		locationManager.desiredAccuracy = kCLLocationAccuracyBest
		locationManager.pausesLocationUpdatesAutomatically = true
		locationManager.allowsBackgroundLocationUpdates = true
		locationManager.activityType = .otherNavigation
		locationManager.requestWhenInUseAuthorization()
		locationManager.distanceFilter = 5
		locationManager.startUpdatingLocation()
	}

    // Apple Park
    static let DefaultLocation = CLLocation(latitude: 37.3346, longitude: -122.0090)
	//static let DefaultAltitude = CLLocationDistance(integerLiteral: 0)
	//static let DefaultSpeed = CLLocationSpeed(integerLiteral: 0)
	//static let DefaultHeading = CLLocationDirection(integerLiteral: 0)

    static var currentLocation: CLLocation {

		guard let location = shared.locationManager.location else {
            return DefaultLocation
        }
        return location
    }

	/// Sats In View Estimator using horizontal and vertical accuracy since
	/// CoreLocation does not have number of sats available
	static var satsInView: Int {
		// Invalid Coordinates
		if shared.locationManager.location?.verticalAccuracy ?? 0 < 0 || shared.locationManager.location?.horizontalAccuracy ?? 0 < 0 {
			return 0
		}
		// If we have a position we have a sat
		var sats = 1
		// If we have a 3D fix we have at least 4 sats
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
		} else if shared.locationManager.location?.horizontalAccuracy ?? 0 <= 300 {
			// Need at least 3 sats to be under 300, over that could be wifi or cell triangulation
			sats = 3
		} else if shared.locationManager.location?.horizontalAccuracy ?? 0 > 300 {
			sats = 2
		}
		return sats
	}
	
	public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

		guard let mostRecentLocation = locations.last else {
			return
		}
		// Extra Smart positioning logic throwing out bad readings from the phone GPS
		let age = -mostRecentLocation.timestamp.timeIntervalSinceNow
		print("Location: HA-\(mostRecentLocation.horizontalAccuracy) VA-\(mostRecentLocation.verticalAccuracy) AGE-\(age)")
		manager.stopUpdatingLocation()
		if age > 10 || mostRecentLocation.horizontalAccuracy < 0 || mostRecentLocation.horizontalAccuracy > 100 {
			print("Bad Location: HA-\(mostRecentLocation.horizontalAccuracy) VA-\(mostRecentLocation.verticalAccuracy) AGE-\(age)")
			manager.startUpdatingLocation()
		} else {
			lastLocation = mostRecentLocation
		}
	}
	
	public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		print("Location manager failed with error: \(error.localizedDescription)")
	}

	public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
		print("Location manager changed the status: \(status)")
	}
}
