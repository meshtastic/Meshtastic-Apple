//
//  TraceRouteFlyover.swift
//  Meshtastic
//
//  Drives the map's MKMapView camera on a guided 3D flythrough along a trace route's legs (forward,
//  then return) — a slow, zoomed-out satellite flyover with a steeply pitched camera that rides
//  above the node elevations, eases into a decelerating "landing" at the end of each leg, then flies
//  the next leg or eases back to the regular map.
//

import MapKit
import QuartzCore
import SwiftUI

@MainActor
final class TraceRouteFlyover: NSObject, ObservableObject {
	/// True while a flyover is animating; drives the play/stop affordance in the map UI.
	@Published private(set) var isFlying = false

	/// Playback speed multiplier: 1 = the base (slow) speed, up to 5 = 400% faster. Live-adjustable
	/// mid-flight from the playback bar.
	@Published var speedMultiplier: Double = 1

	/// The map to drive. Set once via `ClusterMapView`'s `onMapCreated` hook.
	weak var mapView: MKMapView?

	/// One flythrough leg: an ordered path with per-point ground altitude.
	private struct Leg {
		let path: [CLLocationCoordinate2D]
		let altitudes: [CLLocationDistance]
		/// Cumulative ground distance (meters) at each index; `cumulative[0] == 0`.
		let cumulative: [CLLocationDistance]
		let totalDistance: CLLocationDistance
		let duration: CFTimeInterval
	}

	private var displayLink: CADisplayLink?
	private var legs: [Leg] = []
	private var currentLeg = 0
	/// Accumulated progress (0...1) through the current leg; advanced each frame by elapsed time
	/// scaled by `speedMultiplier`, so the speed can change live without a jump.
	private var legProgress: Double = 0
	/// > 0 while holding the slow "landing" at the end of a leg; the next leg (or the map) follows.
	private var holdUntil: CFTimeInterval = 0
	private var savedCamera: MKMapCamera?
	/// The map's basemap config from before the flyover, restored when it ends.
	private var savedConfiguration: MKMapConfiguration?

	/// Smoothed camera heading/altitude carried frame-to-frame (and across legs) so the camera eases
	/// through corners and leg transitions instead of snapping.
	private var smoothedHeading: CLLocationDirection = 0
	private var smoothedAltitude: CLLocationDistance = 0
	private var lastTimestamp: CFTimeInterval = 0
	private var headingInitialized = false

	/// Camera tilt (degrees) — high for a dramatic, near-horizon 3D look.
	private let pitch: CGFloat = 70

	/// Cinematic ground speed (meters/second) the camera tracks along the route. Lower = slower.
	private static let groundSpeed: CLLocationDistance = 5.5

	/// Seconds the camera holds its slow landing at the end of each leg.
	private static let landingHold: CFTimeInterval = 1.6

	/// Begin a flythrough over the given legs (e.g. `[forward, return]`); each needs >= 2 points and
	/// carries optional per-point ground altitude. Switches the map to a 3D satellite basemap, flies
	/// each leg with an eased takeoff + decelerating landing + brief hold, then flies the next leg or
	/// eases back to the prior camera + basemap.
	func start(legs routeLegs: [[(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance)]]) {
		guard let mapView else { return }
		stop(restoreCamera: false)

		legs = routeLegs.compactMap { points -> Leg? in
			guard points.count >= 2 else { return nil }
			let path = points.map { $0.coordinate }
			var cumulative: [CLLocationDistance] = [0]
			var running: CLLocationDistance = 0
			for i in 1..<path.count {
				running += distance(path[i - 1], path[i])
				cumulative.append(running)
			}
			guard running > 0 else { return nil }
			let duration = min(max(running / Self.groundSpeed, 20), 240)
			return Leg(path: path, altitudes: points.map { $0.altitude }, cumulative: cumulative, totalDistance: running, duration: duration)
		}
		guard !legs.isEmpty else { return }

		currentLeg = 0
		legProgress = 0
		holdUntil = 0
		lastTimestamp = 0
		headingInitialized = false
		savedCamera = mapView.camera.copy() as? MKMapCamera

		// Always fly over a 3D satellite basemap (realistic elevation), whatever the current layer is.
		savedConfiguration = mapView.preferredConfiguration
		mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)

		isFlying = true
		let link = CADisplayLink(target: self, selector: #selector(step(_:)))
		link.add(to: .main, forMode: .common)
		displayLink = link
	}

	/// Stop any running flyover. When `restoreCamera` is true (the default), eases back to the camera
	/// from before the flyover. Always restores the prior basemap.
	func stop(restoreCamera: Bool = true) {
		displayLink?.invalidate()
		displayLink = nil
		if isFlying, let mapView {
			if let savedConfiguration { mapView.preferredConfiguration = savedConfiguration }
			if restoreCamera, let savedCamera { mapView.setCamera(savedCamera, animated: true) }
		}
		savedConfiguration = nil
		savedCamera = nil
		legs = []
		isFlying = false
	}

	@objc private func step(_ link: CADisplayLink) {
		guard let mapView, currentLeg < legs.count else { stop(restoreCamera: true); return }
		let now = link.timestamp
		let dt = lastTimestamp == 0 ? (1.0 / 60.0) : max(now - lastTimestamp, 1.0 / 240.0)
		lastTimestamp = now

		// Holding the slow landing at the end of a leg → then fly the next leg or return to the map.
		if holdUntil > 0 {
			if now < holdUntil { return }
			holdUntil = 0
			currentLeg += 1
			legProgress = 0
			if currentLeg >= legs.count { stop(restoreCamera: true) }
			return
		}

		let leg = legs[currentLeg]
		// Advance through the leg by elapsed time scaled by the live speed multiplier.
		legProgress = min(legProgress + dt * speedMultiplier / leg.duration, 1)
		let rawProgress = legProgress
		// Even, constant cruising speed for most of the leg (nature-documentary feel), then a smooth
		// deceleration into the landing over the final stretch — no slow takeoff or fast middle.
		let tail = 0.22
		let cruise = 1.0 / (1.0 - tail / 2.0)   // constant-phase speed so the leg still ends at 1.0
		let eased: Double
		if rawProgress <= 1 - tail {
			eased = cruise * rawProgress
		} else {
			let u = (rawProgress - (1 - tail)) / tail
			eased = cruise * ((1 - tail) + tail * (u - u * u / 2))
		}
		let target = min(eased, 1) * leg.totalDistance
		let current = point(leg, atArcLength: target)

		// Aim further along the leg so the camera curves through corners instead of snapping.
		let lookAhead = min(max(leg.totalDistance * 0.12, 120), 2_000)
		let aim = point(leg, atArcLength: target + lookAhead)

		let canAim = distance(current, aim) > 1
		let targetHeading = canAim
			? bearing(from: current, to: aim)
			: (headingInitialized ? smoothedHeading : bearing(from: leg.path[0], to: leg.path[leg.path.count - 1]))

		// Sit well back (zoomed out), and ride above the node elevations when altitude data is present.
		let groundAltitude = max(altitude(leg, atArcLength: target), 0)
		let targetAltitude = min(max(distance(current, aim) * 4.0, 2_500) + groundAltitude, 90_000)

		if !headingInitialized {
			smoothedHeading = targetHeading
			smoothedAltitude = targetAltitude
			headingInitialized = true
		} else {
			// Frame-rate-independent exponential smoothing → smooth, banked-feeling turns + transitions.
			let kHeading = 1 - exp(-dt / 0.45)
			let kAltitude = 1 - exp(-dt / 0.7)
			var delta = (targetHeading - smoothedHeading).truncatingRemainder(dividingBy: 360)
			if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
			smoothedHeading = (smoothedHeading + delta * kHeading).truncatingRemainder(dividingBy: 360)
			if smoothedHeading < 0 { smoothedHeading += 360 }
			smoothedAltitude += (targetAltitude - smoothedAltitude) * kAltitude
		}

		mapView.camera = MKMapCamera(lookingAtCenter: current, fromDistance: smoothedAltitude, pitch: pitch, heading: smoothedHeading)

		// Reached the end of this leg → begin the slow landing hold.
		if rawProgress >= 1 { holdUntil = now + Self.landingHold }
	}

	/// Coordinate at a cumulative ground distance along `leg` (clamped to the leg ends).
	private func point(_ leg: Leg, atArcLength s: CLLocationDistance) -> CLLocationCoordinate2D {
		let (idx, frac) = segment(leg, atArcLength: min(max(s, 0), leg.totalDistance))
		let a = leg.path[idx], b = leg.path[idx + 1]
		return CLLocationCoordinate2D(
			latitude: a.latitude + (b.latitude - a.latitude) * frac,
			longitude: a.longitude + (b.longitude - a.longitude) * frac
		)
	}

	/// Interpolated ground altitude (meters) at a cumulative distance; 0 when no altitude data.
	private func altitude(_ leg: Leg, atArcLength s: CLLocationDistance) -> CLLocationDistance {
		guard leg.altitudes.count == leg.path.count else { return 0 }
		let (idx, frac) = segment(leg, atArcLength: min(max(s, 0), leg.totalDistance))
		return leg.altitudes[idx] + (leg.altitudes[idx + 1] - leg.altitudes[idx]) * frac
	}

	/// The leg segment index + fractional position within it for a cumulative distance.
	private func segment(_ leg: Leg, atArcLength s: CLLocationDistance) -> (index: Int, fraction: Double) {
		var idx = 0
		while idx < leg.cumulative.count - 2 && leg.cumulative[idx + 1] < s { idx += 1 }
		let segStart = leg.cumulative[idx]
		let segLength = max(leg.cumulative[idx + 1] - segStart, 0.0001)
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
