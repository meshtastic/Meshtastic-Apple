import CoreLocation

class LocationHelper: NSObject, ObservableObject {

    static let shared = LocationHelper()

    // Apple Park
    static let DefaultLocation = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
	
	static let DefaultAltitude = CLLocationDistance(integerLiteral: 0)

    static var currentLocation: CLLocationCoordinate2D {

        guard let location = shared.locationManager.location else {
            return DefaultLocation
        }
        return location.coordinate
    }

	static var currentAltitude: CLLocationDistance {

		guard let altitude = shared.locationManager.location?.altitude else {
			return DefaultAltitude
		}
		return altitude
	}

    private let locationManager = CLLocationManager()

    private override init() {

        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
}

extension LocationHelper: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("Location manager changed the status: \(status)")
    }
}
