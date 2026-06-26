//
//  TraceRouteFlyover.swift
//  Meshtastic
//
//  Drives the map's MKMapView camera on a guided 3D flythrough along a trace route's ordered
//  node coordinates — flying low with a pitched camera, heading along each segment.
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
	/// Cumulative ground distance (meters) at each path index; `cumulative[0] == 0`.
	private var cumulative: [CLLocationDistance] = []
	private var totalDistance: CLLocationDistance = 0
	private var startTimestamp: CFTimeInterval = 0
	private var duration: CFTimeInterval = 0
	private var savedCamera: MKMapCamera?

	/// Camera tilt (degrees) for the 3D look.
	private let pitch: CGFloat = 55

	/// Begin a flyover along `coordinates` (need at least two). Restores the prior camera when it
	/// finishes or is stopped by the user.
	func start(coordinates: [CLLocationCoordinate2D]) {
		guard let mapView, coordinates.count >= 2 else { return }
		stop(restoreCamera: false)

		path = coordinates
		cumulative = [0]
		var running: CLLocationDistance = 0
		for i in 1..<path.count {
			running += distance(path[i - 1], path[i])
			cumulative.append(running)
		}
		totalDistance = running
		guard totalDistance > 0 else { return }

		// Pace the tour by segment count so longer routes get a little more time, clamped to a
		// watchable window.
		duration = min(max(Double(path.count - 1) * 3.0, 6), 40)
		savedCamera = mapView.camera.copy() as? MKMapCamera
		startTimestamp = 0
		isFlying = true

		let link = CADisplayLink(target: self, selector: #selector(step(_:)))
		link.add(to: .main, forMode: .common)
		displayLink = link
	}

	/// Stop any running flyover. When `restoreCamera` is true (the default, e.g. user tapped Stop),
	/// eases back to the camera from before the flyover.
	func stop(restoreCamera: Bool = true) {
		displayLink?.invalidate()
		displayLink = nil
		if restoreCamera, isFlying, let mapView, let savedCamera {
			mapView.setCamera(savedCamera, animated: true)
		}
		savedCamera = nil
		isFlying = false
	}

	@objc private func step(_ link: CADisplayLink) {
		guard let mapView, totalDistance > 0 else { stop(restoreCamera: false); return }
		if startTimestamp == 0 { startTimestamp = link.timestamp }
		let progress = min((link.timestamp - startTimestamp) / duration, 1)

		// Constant ground speed: map progress to a distance, then to a position on the path.
		let target = progress * totalDistance
		var idx = 0
		while idx < cumulative.count - 2 && cumulative[idx + 1] < target { idx += 1 }
		let segStart = cumulative[idx]
		let segLength = max(cumulative[idx + 1] - segStart, 0.0001)
		let frac = min(max((target - segStart) / segLength, 0), 1)

		let a = path[idx], b = path[idx + 1]
		let current = CLLocationCoordinate2D(
			latitude: a.latitude + (b.latitude - a.latitude) * frac,
			longitude: a.longitude + (b.longitude - a.longitude) * frac
		)

		// Look toward the end of the current segment; pull the camera back proportional to the
		// segment length so both short hops and long legs stay framed.
		let heading = bearing(from: current, to: b)
		let altitude = min(max(distance(a, b) * 1.6, 700), 90_000)
		mapView.camera = MKMapCamera(lookingAtCenter: current, fromDistance: altitude, pitch: pitch, heading: heading)

		if progress >= 1 { stop(restoreCamera: false) }
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
