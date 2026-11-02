//
//  CinemaHeadTracker.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
#if os(visionOS)
import ARKit
import OSLog
import QuartzCore
import simd

/// Where the viewer's head is in the cinema, from world tracking, so a card can be hung from the
/// viewer rather than from the painted image's eye point. Runs while the cinema is open; asking
/// for the head's own position needs no permission.
@MainActor
final class CinemaHeadTracker {
	private let session = ARKitSession()
	private let provider = WorldTrackingProvider()
	private var running = false
	/// Set by a stop while the session is still starting, so it's stopped once it has.
	private var stopRequested = false

	func start() async {
		guard !running, WorldTrackingProvider.isSupported else { return }
		stopRequested = false
		do {
			try await session.run([provider])
			guard !stopRequested else {
				session.stop()
				return
			}
			running = true
		} catch {
			Logger.services.error("🎬 [Cinema] Head tracking couldn't start: \(error.localizedDescription, privacy: .public)")
		}
	}

	func stop() {
		stopRequested = true
		guard running else { return }
		session.stop()
		running = false
	}

	/// The head's position in the space now. Nil until tracking is up.
	var headPosition: SIMD3<Float>? {
		guard running, provider.state == .running,
			  let anchor = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
			  anchor.isTracked else { return nil }
		let transform = anchor.originFromAnchorTransform
		return SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
	}
}
#endif
