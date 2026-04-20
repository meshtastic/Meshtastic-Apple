//
//  FoxhuntCompassView.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import SwiftUI
import CoreLocation
import WatchKit

/// A compass view optimised for Apple Watch that points toward a target
/// mesh node. Designed for "foxhunt" (radio direction-finding) scenarios.
///
/// Features:
/// - Rotating compass dial showing heading
/// - Bearing arrow pointing toward the target node
/// - Distance readout
/// - Haptic feedback when aligned with the target (within 10°)
/// - Hot/warm/cold colour coding based on distance
struct FoxhuntCompassView: View {

	let node: MeshNode
	@ObservedObject var locationManager: WatchLocationManager

	@State private var inAlignment = false
	private let alignmentTolerance: Double = 10.0

	/// Half a mile in metres – the maximum distance for foxhunt targets.
	static let maxDistanceMetres: Double = 804.672

	// MARK: - Body

	var body: some View {
		GeometryReader { geometry in
			let size = min(geometry.size.width, geometry.size.height)
			let dialRadius = size * 0.48

			ZStack {
				// Fixed heading indicator at top of ring
				Image(systemName: "triangle.fill")
					.font(.system(size: 8, weight: .bold))
					.foregroundStyle(.white.opacity(0.9))
					.rotationEffect(.degrees(180))
					.offset(y: -(dialRadius + 6))

				// Rotating compass group
				ZStack {
					// Outer ring
					Circle()
						.stroke(Color.primary.opacity(0.3), lineWidth: 3)
						.frame(width: dialRadius * 2 + 8, height: dialRadius * 2 + 8)

					// Tick marks (every 10° for watch readability)
					ForEach(0..<36, id: \.self) { i in
						let deg = Double(i) * 10
						WatchTickMark(degree: deg, radius: dialRadius)
					}

					// Cardinal labels
					ForEach(WatchCompassLabel.allLabels, id: \.degrees) { label in
						Text(label.text)
							.font(.system(size: label.isCardinal ? 11 : 8, weight: label.isCardinal ? .bold : .medium))
							.foregroundStyle(label.degrees == 0 ? .orange : .primary)
							.rotationEffect(.degrees(-label.degrees + locationManager.heading))
							.offset(y: -(dialRadius - 14))
							.rotationEffect(.degrees(label.degrees))
					}

					// North indicator
					WatchTriangle()
						.fill(.orange)
						.frame(width: 7, height: 6)
						.offset(y: -(dialRadius + 3))

					// Centre readout (includes distance)
					centreReadout(dialRadius: dialRadius)

					// Bearing arrow to target
					if let bearing = bearingToNode() {
						// Directional cone showing general heading direction
						DirectionCone(
							bearing: bearing,
							heading: locationManager.heading,
							radius: dialRadius + 4,
							color: distanceColor
						)

						Image(systemName: "location.north.fill")
							.font(.system(size: 26, weight: .bold))
							.foregroundStyle(distanceColor)
							.shadow(color: distanceColor.opacity(0.8), radius: 6)
							.offset(y: -(dialRadius + 16))
							.rotationEffect(.degrees(bearing))
							.onChange(of: locationManager.heading) {
								checkAlignment(bearing: bearing, heading: locationManager.heading)
							}
					}
				}
				.rotationEffect(.degrees(-locationManager.heading))

				// Node short name circle at top
				WatchCircleText(
					text: node.shortName.isEmpty ? "?" : node.shortName,
					color: WatchCircleText.color(for: node.num),
					circleSize: 26
				)
				.offset(y: -(dialRadius + 32))
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.onAppear {
			locationManager.startUpdates()
		}
		.onDisappear {
			locationManager.stopUpdates()
		}
	}

	// MARK: - Centre readout

	@ViewBuilder
	private func centreReadout(dialRadius: CGFloat) -> some View {
		let textColor: Color = distanceColor.isWatchLight ? .black : .white

		ZStack {
			Circle()
				.fill(distanceColor)
				.overlay(
					Circle().stroke(textColor.opacity(0.6), lineWidth: 2)
				)
				.frame(width: dialRadius * 1.1, height: dialRadius * 1.1)

			VStack(spacing: 1) {
				Text(headingText)
					.font(.system(size: 24, weight: .light, design: .rounded))
					.monospacedDigit()
					.foregroundStyle(textColor)

				if let bearing = bearingToNode() {
					Text("\(String(format: "%.0f°", bearing))")
						.font(.system(size: 12, weight: .medium, design: .rounded))
						.foregroundStyle(textColor.opacity(0.8))
				}

				if let dist = distanceToNode() {
					Text(formatDistance(dist))
						.font(.system(size: 12, weight: .semibold, design: .rounded))
						.foregroundStyle(textColor.opacity(0.8))
				}
			}
		}
		.rotationEffect(.degrees(locationManager.heading))
	}

	// MARK: - Calculations

	private var headingText: String {
		"\(Int(locationManager.heading.rounded()) % 360)°"
	}

	private func bearingToNode() -> Double? {
		guard let target = node.coordinate,
			  let user = locationManager.currentLocation?.coordinate else { return nil }
		return Self.bearingBetween(from: user, to: target)
	}

	private func distanceToNode() -> CLLocationDistance? {
		guard let userLoc = locationManager.currentLocation else { return nil }
		return node.distance(from: userLoc)
	}

	/// Colour that shifts from red (far) → yellow (mid) → green (close).
	private var distanceColor: Color {
		guard let dist = distanceToNode() else { return .red }
		let ratio = min(dist / Self.maxDistanceMetres, 1.0)
		if ratio > 0.66 { return .red }
		if ratio > 0.33 { return .yellow }
		return .green
	}

	private func checkAlignment(bearing: Double, heading: Double) {
		let rawDiff = abs(heading - bearing).truncatingRemainder(dividingBy: 360)
		let diff = min(rawDiff, 360 - rawDiff)

		if diff <= alignmentTolerance {
			if !inAlignment {
				inAlignment = true
				WKInterfaceDevice.current().play(.click)
			}
		} else {
			inAlignment = false
		}
	}

	private func formatDistance(_ distance: CLLocationDistance) -> String {
		let measurement = Measurement(value: distance, unit: UnitLength.meters)
		let formatter = MeasurementFormatter()
		formatter.unitOptions = .naturalScale
		formatter.numberFormatter.maximumFractionDigits = 0
		return formatter.string(from: measurement)
	}

	// MARK: - Bearing maths (same algorithm as the main app)

	static func bearingBetween(from user: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) -> Double {
		let lat1 = user.latitude * .pi / 180
		let lon1 = user.longitude * .pi / 180
		let lat2 = target.latitude * .pi / 180
		let lon2 = target.longitude * .pi / 180
		let dLon = lon2 - lon1
		let y = sin(dLon) * cos(lat2)
		let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
		var bearing = atan2(y, x) * 180 / .pi
		if bearing < 0 { bearing += 360 }
		return bearing
	}
}

// MARK: - Direction Cone (Backtrack-style scope)

/// A translucent cone drawn from the centre of the compass toward the
/// bearing, giving a visual "scope" so the user can see when they are
/// heading in roughly the right direction.
private struct DirectionCone: View {
	let bearing: Double
	let heading: Double
	let radius: CGFloat
	let color: Color

	/// Half-width of the cone in degrees.
	private let coneHalfAngle: Double = 20

	var body: some View {
		let onTarget = isOnTarget

		ConeShape(halfAngle: coneHalfAngle, radius: radius)
			.fill(
				RadialGradient(
					colors: [
						color.opacity(onTarget ? 0.55 : 0.3),
						color.opacity(onTarget ? 0.25 : 0.08)
					],
					center: .center,
					startRadius: 0,
					endRadius: radius
				)
			)
			.rotationEffect(.degrees(bearing))
	}

	private var isOnTarget: Bool {
		let rawDiff = abs(heading - bearing).truncatingRemainder(dividingBy: 360)
		let diff = min(rawDiff, 360 - rawDiff)
		return diff <= coneHalfAngle
	}
}

private struct ConeShape: Shape {
	let halfAngle: Double
	let radius: CGFloat

	func path(in rect: CGRect) -> Path {
		let center = CGPoint(x: rect.midX, y: rect.midY)
		let startAngle = Angle(degrees: -90 - halfAngle)
		let endAngle = Angle(degrees: -90 + halfAngle)

		var path = Path()
		path.move(to: center)
		path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
		path.closeSubpath()
		return path
	}
}

// MARK: - Watch-sized compass sub-views

private struct WatchTickMark: View {
	let degree: Double
	let radius: CGFloat

	var body: some View {
		let isCardinal = degree.truncatingRemainder(dividingBy: 90) == 0
		let isMajor = degree.truncatingRemainder(dividingBy: 30) == 0
		let length: CGFloat = isCardinal ? 8 : (isMajor ? 5 : 3)
		let width: CGFloat = isCardinal ? 2 : 1

		Capsule()
			.fill(isCardinal ? Color.primary : Color.primary.opacity(isMajor ? 0.7 : 0.3))
			.frame(width: width, height: length)
			.offset(y: -(radius - length / 2))
			.rotationEffect(.degrees(degree))
	}
}

private struct WatchTriangle: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.move(to: CGPoint(x: rect.midX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
		path.closeSubpath()
		return path
	}
}

private struct WatchCompassLabel {
	let degrees: Double
	let text: String
	let isCardinal: Bool

	static let allLabels: [WatchCompassLabel] = [
		WatchCompassLabel(degrees: 0,   text: "N",  isCardinal: true),
		WatchCompassLabel(degrees: 45,  text: "NE", isCardinal: false),
		WatchCompassLabel(degrees: 90,  text: "E",  isCardinal: true),
		WatchCompassLabel(degrees: 135, text: "SE", isCardinal: false),
		WatchCompassLabel(degrees: 180, text: "S",  isCardinal: true),
		WatchCompassLabel(degrees: 225, text: "SW", isCardinal: false),
		WatchCompassLabel(degrees: 270, text: "W",  isCardinal: true),
		WatchCompassLabel(degrees: 315, text: "NW", isCardinal: false)
	]
}

// MARK: - Color helper

extension Color {
	/// Quick luminance check so center text is readable on the distance color.
	var isWatchLight: Bool {
		// Approximate: yellow and lighter colours are "light"
		if self == .yellow || self == .orange || self == .white { return true }
		// For arbitrary colours, resolve RGBA and compute relative luminance
		guard let components = cgColor?.components, components.count >= 3 else { return false }
		let luminance = 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
		return luminance > 0.6
	}
}
