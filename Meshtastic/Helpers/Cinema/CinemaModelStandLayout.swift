//
//  CinemaModelStandLayout.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
import simd

/// Where the card hangs beside the model on the cinema's stand, and how large the model can be
/// made. Kept apart from the stand so it can be checked without a scene.
enum CinemaModelStandLayout {
	/// The model can stand at up to this many times its real size, to read its screen.
	static let maximumZoom: Float = 5

	/// The model on its stand at real size: how tall, and half how wide.
	struct Size: Equatable {
		var height: Float
		var halfWidth: Float

		static let none = Size(height: 0, halfWidth: 0)
	}

	static func clampZoom(_ zoom: Float) -> Float {
		guard zoom.isFinite else { return 1 }
		return min(max(zoom, 1), maximumZoom)
	}

	/// The card's center, in meters from the stand's base. The card's bottom sits at half the
	/// model's height, up to a hand's width, so the radio's buttons on it stay near its screen; and
	/// it stands clear of the model's side however large the model is made.
	static func cardOffset(stand: Size, zoom: Float, cardWidth: Float, cardHeight: Float) -> SIMD3<Float> {
		let zoom = clampZoom(zoom)
		let height = max(stand.height, 0.08) * zoom
		let bottom = min(height / 2, 0.1)
		let x = max(0.2, stand.halfWidth * zoom + cardWidth / 2 + 0.04)
		return [x, bottom + cardHeight / 2, 0]
	}
}
