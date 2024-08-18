import CoreLocation
import OSLog
import SwiftUI

// to be removed. currently a legacy wrapper for LocationManaged
final class LocationsHandler: ObservableObject {
	static let shared = LocationsHandler()

	@Published
	var locationsArray: [CLLocation] = {
		[LocationManager.shared.getSafeLastKnownLocation()]
	}()

	private init() {

	}
}
