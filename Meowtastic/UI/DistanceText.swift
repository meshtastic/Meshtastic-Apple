import SwiftUI
import CoreLocation
import MapKit

struct DistanceText: View {
	var meters: CLLocationDistance

	@ViewBuilder
	var body: some View {
		let formatter = MKDistanceFormatter()
		let distanceFormatted = formatter.string(fromDistance: Double(meters))

		Text(distanceFormatted + " away")
	}
}
