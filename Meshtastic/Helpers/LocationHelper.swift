import CoreLocation

class LocationHelper: NSObject, ObservableObject {

    static let shared = LocationHelper()

    // Apple Park
    static let DefaultLocation = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
	
	static let DefaultAltitude = CLLocationDistance(integerLiteral: 0)
	static let DefaultSpeed = CLLocationSpeed(integerLiteral: 0)
	static let DefaultHeading = CLLocationDirection(integerLiteral: 0)
	static let DefaultTime = Date.init(timeIntervalSince1970: 0)

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
	
	static var currentSpeed: CLLocationSpeed {

		guard let speed = shared.locationManager.location?.speed else {
			return DefaultSpeed
		}
		return speed
	}
	
	static var currentHeading: CLLocationDirection {

		guard let speed = shared.locationManager.location?.course else {
			return DefaultHeading
		}
		return speed
	}
	
	static var currentTimestamp: Date {

		guard let timestamp = shared.locationManager.location?.timestamp else {
			return DefaultTime
		}
		return timestamp
	}
	
	static var satsInView: Int {
		
		var sats = 0
		
		if shared.locationManager.location?.verticalAccuracy ?? 0 > 0 {
			sats = 4
			
			if 0...60 ~= shared.locationManager.location?.horizontalAccuracy ?? 0{
				sats = 6
			}
			
		} else if shared.locationManager.location?.verticalAccuracy ?? 0 < 0 && 60...300 ~= shared.locationManager.location?.horizontalAccuracy ?? 0 {
			sats = 3
		} else if shared.locationManager.location?.verticalAccuracy ?? 0 < 0 && shared.locationManager.location?.horizontalAccuracy ?? 0 > 300 {
			sats = 2
		}
		return sats
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
