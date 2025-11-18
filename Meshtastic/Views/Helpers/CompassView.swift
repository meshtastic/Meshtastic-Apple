//
//  CompassView.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 11/14/25.
//

import SwiftUI
import CoreLocation
import UIKit

struct CompassView: View {

	/// Single waypoint parameter
	let waypointLocation: CLLocationCoordinate2D?
	
	let waypointName: String?
	
	let color: Color

	@ObservedObject private var locationsHandler = LocationsHandler.shared

	// Haptic alignment tracking
	private let alignmentTolerance: Double = 5.0
	@State private var inAlignment = false

	// Compute bearing from user → waypoint
	private func bearingToWaypoint() -> Double? {
		guard
			let waypoint = waypointLocation,
			let user = LocationsHandler.currentLocation
		else { return nil }

		return BearingCalculator.bearingBetween(
			userLocation: user,
			waypoint: waypoint
		)
	}

	// Trigger a vibration if aligned with waypoint
	private func checkAlignment(bearing: Double,heading: Double) {
		// Compute minimal angular difference between heading and bearing in [0, 180]
		  let rawDiff = abs(heading - bearing).truncatingRemainder(dividingBy: 360)
		  let diff = min(rawDiff, 360 - rawDiff)
		
		if diff <= alignmentTolerance {
			if !inAlignment {
				inAlignment = true
				let generator = UIImpactFeedbackGenerator(style: .heavy)
				generator.impactOccurred()
			}
		} else {
			inAlignment = false
		}
	}

	
	private func distanceToWaypoint() -> CLLocationDistance? {
		guard
			let waypoint = waypointLocation,
			let user = LocationsHandler.currentLocation
		else { return nil }
		
		let userLocation = CLLocation(latitude: user.latitude, longitude: user.longitude)
		let waypointLocation = CLLocation(latitude: waypoint.latitude, longitude: waypoint.longitude)
		
		return userLocation.distance(from: waypointLocation)
	}

	// Format distance with localization
	private func formatDistance(_ distance: CLLocationDistance) -> String {
		let measurement = Measurement(value: distance, unit: UnitLength.meters)
		let formatter = MeasurementFormatter()
		formatter.unitOptions = .naturalScale
		formatter.numberFormatter.maximumFractionDigits = 2
		return formatter.string(from: measurement)
	}
	
	
	var body: some View {
		NavigationStack{
			VStack(spacing: 15) {
				
				VStack(spacing: 8) {
					Text(waypointName ?? "Waypoint")
						.font(.title2)
						.bold()
						.foregroundColor(color ?? Color.orange)
					
					if let wp = waypointLocation {
						HStack{
							Image(systemName: "mappin.and.ellipse")
							Text("\(String(format: "%.4f", wp.latitude)), \(String(format: "%.4f", wp.longitude))")
							.font(.subheadline)
						}
						
						if let distance = distanceToWaypoint() {
							HStack{
								Image(systemName: "lines.measurement.horizontal")
								Text("Distance: \(formatDistance(distance))")
									.font(.subheadline)
									.fontWeight(.semibold)
							}
						}
						HStack{
							Image(systemName: "location.north")
							if let bearing = bearingToWaypoint() {
								Text("Bearing: \(String(format: "%.0f°", bearing))")
									.font(.subheadline)
							} else {
								Text("Bearing: N/A")
									.font(.subheadline)
							}
						}
					}
				}
				.padding()
				
				Capsule()
					.frame(width: 5, height: 50)
				ZStack {
					
					// Cardinal/degree markers
					ForEach(Marker.markers(), id: \.self) { marker in
						CompassMarkerView(
							marker: marker,
							compassDegrees: -locationsHandler.heading
						)
					}
					
					// Waypoint bearing indicator
					if let bearing = bearingToWaypoint() {
						WaypointMarkerView(
							bearing: bearing,
							compassDegrees: locationsHandler.heading,
							color: color
						)
						// Move waypoint marker outside compass
						.onChange(of: locationsHandler.heading) { _, _ in
							checkAlignment(bearing: bearing,heading:locationsHandler.heading)
						}
					}
					
				}
				.frame(width: 300, height: 300)
				.rotationEffect(Angle(degrees: -locationsHandler.heading))
				.statusBar(hidden: true)
				.onAppear {
					locationsHandler.startHeadingUpdates()
					locationsHandler.startLocationUpdates()
				}
				.onDisappear {
					locationsHandler.stopHeadingUpdates()
					locationsHandler.stopLocationUpdates()
				}
				.navigationTitle("Compass")
			}
		}
	}
}


// MARK: - Waypoint Marker View

struct WaypointMarkerView: View {
	let bearing: Double
	let compassDegrees: Double
	let color: Color

	var body: some View {
			Circle()
				.frame(width: 20, height: 20)
				.foregroundColor(color)
				.offset(y: -170)
				.rotationEffect(Angle(degrees: bearing))
	}

	private func textAngle() -> Angle {
		Angle(degrees: -compassDegrees - bearing)
	}
}


// MARK: - Bearing Calculator

struct BearingCalculator {

	static func bearingBetween(
		userLocation: CLLocationCoordinate2D,
		waypoint: CLLocationCoordinate2D
	) -> Double {

		let lat1 = userLocation.latitude * .pi / 180
		let lon1 = userLocation.longitude * .pi / 180
		let lat2 = waypoint.latitude * .pi / 180
		let lon2 = waypoint.longitude * .pi / 180

		let dLon = lon2 - lon1

		let y = sin(dLon) * cos(lat2)
		let x = cos(lat1) * sin(lat2)
			  - sin(lat1) * cos(lat2) * cos(dLon)

		var bearing = atan2(y, x) * 180 / .pi
		if bearing < 0 { bearing += 360 }

		return bearing
	}
}


// MARK: - Marker Model

struct Marker: Hashable {
	let degrees: Double
	let label: String

	init(degrees: Double, label: String = "") {
		self.degrees = degrees
		self.label = label
	}

	func degreeText() -> String {
		return String(format: "%.0f", self.degrees)
	}

	static func markers() -> [Marker] {
		return [
			Marker(degrees: 0, label: "N"),
			Marker(degrees: 30),
			Marker(degrees: 60),
			Marker(degrees: 90, label: "E"),
			Marker(degrees: 120),
			Marker(degrees: 150),
			Marker(degrees: 180, label: "S"),
			Marker(degrees: 210),
			Marker(degrees: 240),
			Marker(degrees: 270, label: "W"),
			Marker(degrees: 300),
			Marker(degrees: 330)
		]
	}
}


// MARK: - Compass Marker View

struct CompassMarkerView: View {
	let marker: Marker
	let compassDegrees: Double

	var body: some View {
		VStack {
			Text(marker.degreeText())
				.fontWeight(.light)
				.rotationEffect(textAngle())

			Capsule()
				.frame(width: capsuleWidth(), height: capsuleHeight())
				.foregroundColor(capsuleColor())

			Text(marker.label)
				.fontWeight(.bold)
				.rotationEffect(textAngle())
				.padding(.bottom, 180)
		}
		.rotationEffect(Angle(degrees: marker.degrees))
	}

	private func capsuleWidth() -> CGFloat {
		marker.degrees == 0 ? 7 : 3
	}

	private func capsuleHeight() -> CGFloat {
		marker.degrees == 0 ? 45 : 30
	}

	private func capsuleColor() -> Color {
		marker.degrees == 0 ? .red : .gray
	}

	private func textAngle() -> Angle {
		Angle(degrees: -compassDegrees - marker.degrees)
	}
}


// MARK: - Preview

struct CompassView_Previews: PreviewProvider {
	static var previews: some View {
		CompassView(
			waypointLocation: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
			waypointName: "Apple Park",
			color: Color.orange
		)
	}
}
