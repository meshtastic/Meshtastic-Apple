//
//  LookoutSiteNearestTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/10/26.
//

import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

@Suite("Fire lookout chosen summit")
struct LookoutSiteNearestTests {

	private struct Site: Equatable {
		let latitude: Double
		let longitude: Double
		var id: String { String(format: "%.4f,%.4f", latitude, longitude) }
		var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
	}

	private func site(_ latitude: Double, _ longitude: Double) -> Site {
		Site(latitude: latitude, longitude: longitude)
	}

	private func nearest(to id: String, in sites: [Site]) -> Site? {
		SpatialLookout.nearest(to: id, in: sites) { $0.coordinate }
	}

	@Test("a summit a few meters off in a new search is still the chosen one")
	func movedALittle() {
		let chosen = site(47.5000, -121.5000)
		let moved = site(47.5003, -121.5002)
		let found = nearest(to: chosen.id, in: [site(47.6, -121.6), moved])
		#expect(found == moved)
	}

	@Test("the nearest of several close summits is the chosen one")
	func nearestWins() {
		let chosen = site(47.5000, -121.5000)
		let near = site(47.5001, -121.5000)
		let farther = site(47.5030, -121.5000)
		#expect(nearest(to: chosen.id, in: [farther, near]) == near)
	}

	@Test("a summit farther than the limit is a different one, and an id that isn't a place finds nothing")
	func farOrInvalid() {
		let chosen = site(47.5000, -121.5000)
		#expect(nearest(to: chosen.id, in: [site(47.52, -121.5)]) == nil)
		#expect(nearest(to: "", in: [chosen]) == nil)
	}
}
