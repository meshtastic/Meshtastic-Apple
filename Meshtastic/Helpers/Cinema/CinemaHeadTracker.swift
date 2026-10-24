//
//  CinemaHeadTracker.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/24/26.
//
#if os(visionOS)
import ARKit
import OSLog
import QuartzCore

/// Where the viewer's head is in the cinema. The tent image was rendered from one point, so the
/// image and the panels over it only line up when they are centered on the viewer's eyes, seated
/// or standing. World tracking needs no permission prompt.
@MainActor
final class CinemaHeadTracker {
	private let session = ARKitSession()
	private let worldTracking = WorldTrackingProvider()
	private var isRunning = false

	func start() async {
		guard WorldTrackingProvider.isSupported else {
			Logger.services.info("🎬 [Cinema] World tracking isn't available; using the seated eye height")
			return
		}
		do {
			try await session.run([worldTracking])
			isRunning = true
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't start world tracking: \(error.localizedDescription, privacy: .public)")
		}
	}

	func stop() {
		session.stop()
		isRunning = false
	}

	/// The head's position in the immersive space, or nil when it isn't being tracked.
	func headPosition() -> SIMD3<Float>? {
		guard isRunning, worldTracking.state == .running,
			  let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
			  anchor.isTracked else {
			return nil
		}
		let translation = anchor.originFromAnchorTransform.columns.3
		return SIMD3(translation.x, translation.y, translation.z)
	}
}
#endif
