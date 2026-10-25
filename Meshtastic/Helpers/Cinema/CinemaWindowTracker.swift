//
//  CinemaWindowTracker.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
#if os(visionOS)
import Foundation
import Observation
import Spatial

/// Where a main window is in the immersive space: its view's transform in `.immersiveSpace`
/// (points, which already include the scale the system gives a window for its distance) and its
/// size in points.
struct CinemaWindowPose: Equatable {
	var transform: AffineTransform3D
	var size: CGSize

	/// The window's corners in `.immersiveSpace`: top left, top right, bottom left, bottom right.
	var corners: [Point3D] {
		[(0, 0), (size.width, 0), (0, size.height), (size.width, size.height)].map { x, y in
			Point3D(x: x, y: y, z: 0).applying(transform)
		}
	}

	/// The first report from a new window comes before the system has placed it: no translation
	/// and a scale of exactly 1. Nothing real looks like that.
	var isPlaced: Bool {
		let t = transform.translation
		let unmoved = abs(t.x) < 0.001 && abs(t.y) < 0.001 && abs(t.z) < 0.001
		let unscaled = abs(transform.scale.width - 1) < 0.000_001 && abs(transform.scale.height - 1) < 0.000_001
		return !(unmoved && unscaled) && size.width > 0 && size.height > 0
	}
}

/// The pose of the one main window the cinema builds its front wall around. With several main
/// windows open, the first one to report keeps it until it goes away. Used on the main thread.
@Observable
final class CinemaWindowTracker {
	private(set) var pose: CinemaWindowPose?
	@ObservationIgnored private var owner: UUID?

	/// A window's new pose, or nil when it closes or the cinema does.
	func report(_ pose: CinemaWindowPose?, from window: UUID) {
		guard owner == nil || owner == window else { return }
		guard let pose else {
			owner = nil
			self.pose = nil
			return
		}
		guard pose.isPlaced else { return }
		owner = window
		if self.pose != pose {
			self.pose = pose
		}
	}
}
#endif
