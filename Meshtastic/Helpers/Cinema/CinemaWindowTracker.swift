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
import SwiftUI

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

/// Where the Spatial Map volume is in the immersive space, so the front wall can keep out of its way.
struct CinemaVolumePose: Equatable {
	var transform: AffineTransform3D
	var bounds: Rect3D

	/// The volume's eight corners in `.immersiveSpace`.
	var corners: [Point3D] {
		let low = bounds.min, high = bounds.max
		return [low.x, high.x].flatMap { x in
			[low.y, high.y].flatMap { y in
				[low.z, high.z].map { z in Point3D(x: x, y: y, z: z).applying(transform) }
			}
		}
	}
}

/// The main windows' poses while the cinema is open, and which of them the front wall is built
/// round. That window, the owner, is also the one held at the cinema size. The first window to be
/// placed becomes the owner; when it closes, the longest-open other window takes over at once with
/// the pose it last reported. Used on the main thread.
@Observable
final class CinemaWindowTracker {
	/// The window the front wall is built round. Watched by the windows, so each knows whether to
	/// hold the cinema size. Changes rarely.
	private(set) var owner: UUID?
	/// Not watched: the cinema reads these every frame, so a drag doesn't redraw any view.
	@ObservationIgnored private var poses: [UUID: CinemaWindowPose] = [:]
	@ObservationIgnored private var opened: [UUID] = []
	@ObservationIgnored private(set) var volume: CinemaVolumePose?

	/// The owner's pose.
	var pose: CinemaWindowPose? {
		owner.flatMap { poses[$0] }
	}

	/// A window's new pose.
	func report(_ pose: CinemaWindowPose, from window: UUID) {
		guard pose.isPlaced else { return }
		if poses[window] == nil {
			opened.append(window)
		}
		poses[window] = pose
		if owner == nil {
			owner = window
		}
	}

	/// A window closed, or the cinema did.
	func remove(_ window: UUID) {
		poses[window] = nil
		opened.removeAll { $0 == window }
		if owner == window {
			owner = opened.first
		}
	}

	/// The Spatial Map volume's new pose, or nil when it closes.
	func reportVolume(_ pose: CinemaVolumePose?) {
		volume = pose
	}

	/// The cinema closed. The volume's pose is kept; it is reported whether the cinema is open or not.
	func reset() {
		owner = nil
		poses = [:]
		opened = []
	}
}

extension View {
	/// Tells the cinema where the Spatial Map volume is, so its front wall doesn't hide the volume.
	/// Always reported, since the volume can be placed before the cinema opens.
	func reportsCinemaVolume(to tracker: CinemaWindowTracker) -> some View {
		onGeometryChange3D(for: CinemaVolumePose?.self) { proxy in
			proxy.transform(in: .immersiveSpace).map { CinemaVolumePose(transform: $0, bounds: proxy.frame(in: .local)) }
		} action: { pose in
			tracker.reportVolume(pose)
		}
		.onDisappear {
			tracker.reportVolume(nil)
		}
	}
}
#endif
