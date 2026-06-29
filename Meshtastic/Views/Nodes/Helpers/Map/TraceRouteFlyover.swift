//
//  TraceRouteFlyover.swift
//  Meshtastic
//
//  Drives the map's MKMapView camera on a guided 3D flythrough along a trace route's ordered
//  node coordinates — a slow, zoomed-out satellite flyover with a steeply pitched camera that
//  rides above the node elevations when altitude data is available.
//

import MapKit
import QuartzCore
import SwiftUI

@MainActor
final class TraceRouteFlyover: NSObject, ObservableObject {
	/// True while a flyover is animating; drives the play/stop affordance in the map UI.
	@Published private(set) var isFlying = false

	/// The map to drive. Set once via `ClusterMapView`'s `onMapCreated` hook.
	weak var mapView: MKMapView?

	private var displayLink: CADisplayLink?
	private var path: [CLLocationCoordinate2D] = []
	/// Ground altitude (meters) for each path point, aligned with `path`; 0 where unknown.
	private var altitudes: [CLLocationDistance] = []
	/// Cumulative ground distance (meters) at each path index; `cumulative[0] == 0`.
	private var cumulative: [CLLocationDistance] = []
	private var totalDistance: CLLocationDistance = 0
	private var startTimestamp: CFTimeInterval = 0
	private var duration: CFTimeInterval = 0
	private var savedCamera: MKMapCamera?
	/// The map's basemap config from before the flyover, restored when it ends.
	private var savedConfiguration: MKMapConfiguration?

	/// Smoothed camera heading/altitude carried frame-to-frame so the camera eases through corners
	/// instead of snapping its heading at each path vertex.
	private var smoothedHeading: CLLocationDirection = 0
	private var smoothedAltitude: CLLocationDistance = 0
	private var lastTimestamp: CFTimeInterval = 0
	private var headingInitialized = false

	/// Camera tilt (degrees) — high for a dramatic, near-horizon 3D look.
	private let pitch: CGFloat = 70

	/// Cinematic ground speed (meters/second) the camera tracks along the route. Lower = slower.
	private static let groundSpeed: CLLocationDistance = 22

	/// Begin a flyover along `routePath` (need at least two points; each carries an optional ground
	/// altitude). Switches the map to a 3D satellite basemap for the duration and restores the prior
	/// camera + basemap when it finishes or is stopped by the user.
	func start(path routePath: [(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance)]) {
		guard let mapView, routePath.count >= 2 else { return }
		stop(restoreCamera: false)

		path = routePath.map { $0.coordinate }
		altitudes = routePath.map { $0.altitude }
		cumulative = [0]
		var running: CLLocationDistance = 0
		for i in 1..<path.count {
			running += distance(path[i - 1], path[i])
			cumulative.append(running)
		}
		totalDistance = running
		guard totalDistance > 0 else { return }

		// Pace by ground distance so the camera holds a steady, watchable speed regardless of how far
		// apart the nodes are, clamped to a sensible window.
		duration = min(max(totalDistance / Self.groundSpeed, 16), 75)
		savedCamera = mapView.camera.copy() as? MKMapCamera

		// Always fly over a 3D satellite basemap (realistic elevation), whatever the current layer is.
		savedConfiguration = mapView.preferredConfiguration
		mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)

		startTimestamp = 0
		lastTimestamp = 0
		headingInitialized = false
		isFlying = true

		let link = CADisplayLink(target: self, selector: #selector(step(_:)))
		link.add(to: .main, forMode: .common)
		displayLink = link
	}

	/// Stop any running flyover. When `restoreCamera` is true (the default, e.g. user tapped Stop),
	/// eases back to the camera from before the flyover. Always restores the prior basemap.
	func stop(restoreCamera: Bool = true) {
		displayLink?.invalidate()
		displayLink = nil
		if isFlying, let mapView {
			if let savedConfiguration { mapView.preferredConfiguration = savedConfiguration }
			if restoreCamera, let savedCamera { mapView.setCamera(savedCamera, animated: true) }
		}
		savedConfiguration = nil
		savedCamera = nil
		isFlying = false
	}

	@objc private func step(_ link: CADisplayLink) {
		guard let mapView, totalDistance > 0 else { stop(restoreCamera: false); return }
		if startTimestamp == 0 { startTimestamp = link.timestamp }
		let dt = lastTimestamp == 0 ? (1.0 / 60.0) : max(link.timestamp - lastTimestamp, 1.0 / 240.0)
		lastTimestamp = link.timestamp

		// Constant ground speed: map progress to a distance, then to a position on the path.
		let progress = min((link.timestamp - startTimestamp) / duration, 1)
		let target = progress * totalDistance
		let current = point(atArcLength: target)

		// Aim at a point further along the path (not just the current segment's end) so the camera
		// curves through corners instead of snapping its heading at each vertex.
		let lookAhead = min(max(totalDistance * 0.12, 120), 2_000)
		let aim = point(atArcLength: target + lookAhead)

		let canAim = distance(current, aim) > 1
		let targetHeading = canAim
			? bearing(from: current, to: aim)
			: (headingInitialized ? smoothedHeading : bearing(from: path[0], to: path[path.count - 1]))

		// Sit well back (zoomed out) proportional to how far ahead the camera can see, and ride above
		// the node elevations along the way when altitude data is present.
		let groundAltitude = max(altitude(atArcLength: target), 0)
		let targetAltitude = min(max(distance(current, aim) * 2.8, 1_200) + groundAltitude, 90_000)

		if !headingInitialized {
			smoothedHeading = targetHeading
			smoothedAltitude = targetAltitude
			headingInitialized = true
		} else {
			// Frame-rate-independent exponential smoothing → smooth, banked-feeling turns rather
			// than an instant snap at each corner.
			let kHeading = 1 - exp(-dt / 0.45)
			let kAltitude = 1 - exp(-dt / 0.7)
			var delta = (targetHeading - smoothedHeading).truncatingRemainder(dividingBy: 360)
			if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
			smoothedHeading = (smoothedHeading + delta * kHeading).truncatingRemainder(dividingBy: 360)
			if smoothedHeading < 0 { smoothedHeading += 360 }
			smoothedAltitude += (targetAltitude - smoothedAltitude) * kAltitude
		}

		mapView.camera = MKMapCamera(lookingAtCenter: current, fromDistance: smoothedAltitude, pitch: pitch, heading: smoothedHeading)

		if progress >= 1 { stop(restoreCamera: false) }
	}

	/// Coordinate at a given cumulative ground distance along the path (clamped to the route ends).
	private func point(atArcLength s: CLLocationDistance) -> CLLocationCoordinate2D {
		let (idx, frac) = segment(atArcLength: min(max(s, 0), totalDistance))
		let a = path[idx], b = path[idx + 1]
		return CLLocationCoordinate2D(
			latitude: a.latitude + (b.latitude - a.latitude) * frac,
			longitude: a.longitude + (b.longitude - a.longitude) * frac
		)
	}

	/// Interpolated ground altitude (meters) at a cumulative distance; 0 when no altitude data.
	private func altitude(atArcLength s: CLLocationDistance) -> CLLocationDistance {
		guard altitudes.count == path.count else { return 0 }
		let (idx, frac) = segment(atArcLength: min(max(s, 0), totalDistance))
		return altitudes[idx] + (altitudes[idx + 1] - altitudes[idx]) * frac
	}

	/// The path segment index + fractional position within it for a cumulative distance.
	private func segment(atArcLength s: CLLocationDistance) -> (index: Int, fraction: Double) {
		var idx = 0
		while idx < cumulative.count - 2 && cumulative[idx + 1] < s { idx += 1 }
		let segStart = cumulative[idx]
		let segLength = max(cumulative[idx + 1] - segStart, 0.0001)
		return (idx, min(max((s - segStart) / segLength, 0), 1))
	}

	private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
		CLLocation(latitude: a.latitude, longitude: a.longitude)
			.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
	}

	private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
		let lat1 = from.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
		let dLon = (to.longitude - from.longitude) * .pi / 180
		let y = sin(dLon) * cos(lat2)
		let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
		let deg = atan2(y, x) * 180 / .pi
		return (deg + 360).truncatingRemainder(dividingBy: 360)
	}
}
