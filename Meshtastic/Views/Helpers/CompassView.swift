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

	private let dialRadius: CGFloat = 140

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
	private func checkAlignment(bearing: Double, heading: Double) {
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

	private func formatDistance(_ distance: CLLocationDistance) -> String {
		let measurement = Measurement(value: distance, unit: UnitLength.meters)
		let formatter = MeasurementFormatter()
		formatter.unitOptions = .naturalScale
		formatter.numberFormatter.maximumFractionDigits = 1
		return formatter.string(from: measurement)
	}

	var body: some View {
		NavigationStack {
			ZStack {
				Color.black.ignoresSafeArea()

				VStack(spacing: 0) {
					// Top fixed heading indicator triangle
					Image(systemName: "triangle.fill")
						.font(.system(size: 14, weight: .bold))
						.foregroundColor(.white)
						.rotationEffect(.degrees(180))
						.padding(.bottom, 4)

					// Rotating compass dial
					ZStack {
						// Outer bezel ring
						Circle()
							.stroke(Color.white.opacity(0.2), lineWidth: 1.5)
							.frame(width: dialRadius * 2 + 20, height: dialRadius * 2 + 20)

						// Tick marks
						ForEach(0..<360, id: \.self) { degree in
							CompassTickMark(degree: Double(degree), radius: dialRadius)
						}

						// Cardinal and intercardinal labels
						ForEach(CompassLabel.allLabels, id: \.degrees) { label in
							CompassLabelView(label: label, radius: dialRadius - 28)
								.rotationEffect(.degrees(-locationsHandler.heading))
						}

						// North triangle indicator at 0°
						CompassNorthIndicator(radius: dialRadius + 2)

						// Degree readout at center
						VStack(spacing: 4) {
							Text(headingText())
								.font(.system(size: 42, weight: .light, design: .rounded))
								.foregroundColor(.white)
								.monospacedDigit()

							if let distance = distanceToWaypoint() {
								Text(formatDistance(distance))
									.font(.system(size: 18, weight: .semibold, design: .rounded))
									.foregroundColor(color)
							}

							if waypointName != nil || waypointLocation != nil {
								Text(waypointName ?? "Waypoint")
									.font(.system(size: 13, weight: .medium))
									.foregroundColor(color.opacity(0.8))
							}
						}

						// Waypoint bearing indicator
						if let bearing = bearingToWaypoint() {
							WaypointMarkerView(
								bearing: bearing,
								radius: dialRadius + 14,
								color: color
							)
							.onChange(of: locationsHandler.heading) { _, _ in
								checkAlignment(bearing: bearing, heading: locationsHandler.heading)
							}
						}
					}
					.frame(width: dialRadius * 2 + 40, height: dialRadius * 2 + 40)
					.rotationEffect(Angle(degrees: -locationsHandler.heading))

					// Bottom info
					if let wp = waypointLocation {
						VStack(spacing: 6) {
							HStack(spacing: 4) {
								Image(systemName: "mappin")
									.font(.system(size: 11))
								Text("\(String(format: "%.4f", wp.latitude)), \(String(format: "%.4f", wp.longitude))")
									.font(.system(size: 12, design: .monospaced))
							}
							.foregroundColor(.white.opacity(0.5))

							if let bearing = bearingToWaypoint() {
								HStack(spacing: 4) {
									Image(systemName: "location.north.fill")
										.font(.system(size: 11))
										.rotationEffect(.degrees(bearing))
									Text("\(String(format: "%.0f°", bearing))")
										.font(.system(size: 12, weight: .medium, design: .monospaced))
								}
								.foregroundColor(color.opacity(0.7))
							}
						}
						.padding(.top, 20)
					}
				}
			}
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
			.toolbarColorScheme(.dark, for: .navigationBar)
		}
	}

	private func headingText() -> String {
		let h = Int(locationsHandler.heading.rounded()) % 360
		return "\(h)°"
	}
}

// MARK: - Compass Tick Mark
struct CompassTickMark: View {
	let degree: Double
	let radius: CGFloat

	var body: some View {
		let isCardinal = degree.truncatingRemainder(dividingBy: 90) == 0
		let isMajor = degree.truncatingRemainder(dividingBy: 30) == 0
		let isMinor = degree.truncatingRemainder(dividingBy: 10) == 0

		let length: CGFloat = isCardinal ? 16 : (isMajor ? 12 : (isMinor ? 8 : 4))
		let width: CGFloat = isCardinal ? 2.5 : (isMajor ? 1.5 : 1)
		let tickColor: Color = isCardinal ? .white : (isMajor ? .white.opacity(0.7) : .white.opacity(0.3))

		// Only draw ticks at 2° intervals
		if Int(degree) % 2 == 0 {
			Capsule()
				.fill(tickColor)
				.frame(width: width, height: length)
				.offset(y: -(radius - length / 2))
				.rotationEffect(.degrees(degree))
		}
	}
}

// MARK: - North Indicator
struct CompassNorthIndicator: View {
	let radius: CGFloat

	var body: some View {
		Triangle()
			.fill(Color.orange)
			.frame(width: 12, height: 10)
			.offset(y: -(radius + 8))
	}
}

struct Triangle: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.move(to: CGPoint(x: rect.midX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
		path.closeSubpath()
		return path
	}
}

// MARK: - Compass Label Model & View
struct CompassLabel {
	let degrees: Double
	let text: String
	let isCardinal: Bool

	static let allLabels: [CompassLabel] = [
		CompassLabel(degrees: 0, text: "N", isCardinal: true),
		CompassLabel(degrees: 45, text: "NE", isCardinal: false),
		CompassLabel(degrees: 90, text: "E", isCardinal: true),
		CompassLabel(degrees: 135, text: "SE", isCardinal: false),
		CompassLabel(degrees: 180, text: "S", isCardinal: true),
		CompassLabel(degrees: 225, text: "SW", isCardinal: false),
		CompassLabel(degrees: 270, text: "W", isCardinal: true),
		CompassLabel(degrees: 315, text: "NW", isCardinal: false)
	]
}

struct CompassLabelView: View {
	let label: CompassLabel
	let radius: CGFloat

	var body: some View {
		Text(label.text)
			.font(.system(size: label.isCardinal ? 18 : 13,
						  weight: label.isCardinal ? .bold : .medium))
			.foregroundColor(label.degrees == 0 ? .orange : .white)
			.rotationEffect(.degrees(-label.degrees))
			.offset(y: -radius)
			.rotationEffect(.degrees(label.degrees))
	}
}

// MARK: - Waypoint Marker View
struct WaypointMarkerView: View {
	let bearing: Double
	let radius: CGFloat
	let color: Color

	var body: some View {
		ZStack {
			// Outer glow
			Image(systemName: "arrowtriangle.up.fill")
				.font(.system(size: 20, weight: .bold))
				.foregroundColor(color.opacity(0.3))
				.offset(y: -(radius + 4))
				.rotationEffect(.degrees(bearing))

			// Arrow
			Image(systemName: "arrowtriangle.up.fill")
				.font(.system(size: 16, weight: .bold))
				.foregroundColor(color)
				.offset(y: -(radius + 5))
				.rotationEffect(.degrees(bearing))
		}
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
