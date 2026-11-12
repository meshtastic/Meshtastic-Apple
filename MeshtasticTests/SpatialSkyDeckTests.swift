//
//  SpatialSkyDeckTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
import CoreLocation
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map sky deck")
struct SpatialSkyDeckTests {

	@Test("the glass box stays within its budget, sits against the wall at z 0 and opens out along +z")
	func meshShape() {
		let parts = SpatialSkyDeck.geometry()
		#expect(Set(parts.keys) == Set(SpatialSkyDeck.Part.allCases))
		let total = parts.values.map(\.triangleCount).reduce(0, +)
		#expect(total > 50 && total < SpatialSkyDeck.triangleBudget, "\(total)")
		let box = (parts[.glass]?.positions ?? []) + (parts[.ceiling]?.positions ?? [])
		let tolerance: Float = 0.0002 * SpatialSkyDeck.scale
		#expect(abs((box.map(\.z).min() ?? 1)) < tolerance)
		#expect(abs((box.map(\.z).max() ?? 0) - SpatialSkyDeck.depth * SpatialSkyDeck.scale) < tolerance)
		#expect(abs((box.map(\.y).min() ?? 1)) < tolerance)
		#expect(abs((box.map(\.y).max() ?? 0) - SpatialSkyDeck.height) < tolerance)
		// Only the braces reach back into the wall.
		#expect((parts[.frame]?.positions.map(\.z).min() ?? 0) > -tolerance * 2)
	}

	@Test("the face is the overhang back from the seat, and the point inside the tower further back")
	func faceBehindSeat() {
		let seat = CLLocationCoordinate2D(latitude: 47.6045, longitude: -122.3305)
		let face = RooftopSites.face(behind: seat, facing: 90)
		let inside = RooftopSites.tower(behind: seat, facing: 90)
		let metersPerLon = SpatialFrame.metersPerDegreeLatitude * cos(seat.latitude * .pi / 180)
		#expect(abs((seat.longitude - face.longitude) * metersPerLon - RooftopSites.deckOverhang) < 0.01)
		#expect(abs(face.latitude - seat.latitude) < 1e-9)
		#expect(inside.longitude < face.longitude)
	}
}
