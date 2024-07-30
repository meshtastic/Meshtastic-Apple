import CoreLocation
import OSLog
import SwiftUI

// to be removed. currently a legacy wrapper for LocationManaged
final class LocationHelper {
	static let shared = LocationHelper()
	static var currentLocation: CLLocationCoordinate2D = {
		LocationManager.shared.getSafeLastKnownLocation().coordinate
	}()

	var locationManager = LocationHelperManager()

	private init() {

	}
}
