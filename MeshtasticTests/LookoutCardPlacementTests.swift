//
//  LookoutCardPlacementTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Fire lookout card placement")
struct LookoutCardPlacementTests {
	private let markerWidth = 6.0
	/// A 380 pt card drawn 1.6 times larger: about 45 cm wide, 22 cm to its edge.
	private let cardHalfWidth: Float = 0.22

	/// Degrees clockwise from straight ahead, and above level, of `point` seen from `eye`.
	private func angles(from eye: SIMD3<Float>, to point: SIMD3<Float>) -> (azimuth: Double, elevation: Double) {
		let d = point - eye
		let flat = Double(simd_length(SIMD2(d.x, d.z)))
		return (atan2(Double(d.x), Double(-d.z)) * 180 / .pi, atan2(Double(d.y), flat) * 180 / .pi)
	}

	@Test("the card hangs at reading distance just right of the marker, as seen from the eye")
	func besideTheMarker() {
		let eye = SIMD3<Float>(0, 1.15, 0)
		let marker = eye + LookoutCardPlacement.direction(azimuth: 30, elevation: 3) * 400
		let center = LookoutCardPlacement.center(eye: eye, marker: marker, markerWidthDegrees: markerWidth, cardHalfWidth: cardHalfWidth)
		#expect(abs(simd_distance(center, eye) - LookoutCardPlacement.distance) < 1e-4)
		let seen = angles(from: eye, to: center)
		let cardHalfDegrees = Double(atan(cardHalfWidth / LookoutCardPlacement.distance)) * 180 / .pi
		#expect(abs(seen.azimuth - (30 + markerWidth / 2 + LookoutCardPlacement.gapDegrees + cardHalfDegrees)) < 0.01)
		#expect(abs(seen.elevation - 3) < 0.01)
	}

	@Test("a standing viewer off the seat still gets the card beside the marker from where they are")
	func followsTheViewer() {
		let seat = SIMD3<Float>(0, 1.15, 0)
		let marker = seat + LookoutCardPlacement.direction(azimuth: -40, elevation: -1) * 300
		let eye = SIMD3<Float>(0.4, 1.65, 0.5)
		let center = LookoutCardPlacement.center(eye: eye, marker: marker, markerWidthDegrees: markerWidth, cardHalfWidth: cardHalfWidth)
		let toMarker = angles(from: eye, to: marker)
		let toCard = angles(from: eye, to: center)
		let cardHalfDegrees = Double(atan(cardHalfWidth / LookoutCardPlacement.distance)) * 180 / .pi
		#expect(abs(toCard.azimuth - toMarker.azimuth - (markerWidth / 2 + LookoutCardPlacement.gapDegrees + cardHalfDegrees)) < 0.01)
		#expect(abs(simd_distance(center, eye) - LookoutCardPlacement.distance) < 1e-4)
		// At the viewer's height, not the seat's.
		#expect(center.y > eye.y - 0.1)
	}

	@Test("a marker down in the valley lifts the card to just under level")
	func staysOffTheSill() {
		let eye = SIMD3<Float>(0, 1.15, 0)
		let marker = eye + LookoutCardPlacement.direction(azimuth: 10, elevation: -8) * 200
		let center = LookoutCardPlacement.center(eye: eye, marker: marker, markerWidthDegrees: markerWidth, cardHalfWidth: cardHalfWidth)
		#expect(abs(angles(from: eye, to: center).elevation - LookoutCardPlacement.lowestDegrees) < 0.01)
	}
}
