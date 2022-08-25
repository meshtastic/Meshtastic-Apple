//
//  DistanceText.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/19/22.
//

import SwiftUI
import CoreLocation
import MapKit

struct DistanceText: View {
	
	var meters: CLLocationDistance
	
	var body: some View {
		
		let distanceFormatter = MKDistanceFormatter()

		Text("Distance: \(distanceFormatter.string(fromDistance: Double(meters)))")
	}
}
