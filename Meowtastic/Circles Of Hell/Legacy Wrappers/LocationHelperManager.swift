import Foundation
import CoreLocation

final class LocationHelperManager {
	var location: CLLocation? = {
		LocationManager.shared.lastKnownLocation
	}()
}
