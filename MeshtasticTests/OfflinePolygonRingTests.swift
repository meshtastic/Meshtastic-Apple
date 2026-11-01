//
//  OfflinePolygonRingTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Foundation
import GISTools
import Testing

@testable import Meshtastic

@Suite("Offline basemap polygon rings")
struct OfflinePolygonRingTests {

	/// A closed square ring, counter-clockwise on the map (positive area) unless `clockwise`.
	private func square(_ west: Double, _ south: Double, _ size: Double, clockwise: Bool = false) -> [GISTools.Coordinate3D] {
		let corners = [(west, south), (west + size, south), (west + size, south + size), (west, south + size)]
		let ordered = clockwise ? corners.reversed() : corners
		let ring = ordered.map { GISTools.Coordinate3D(latitude: $0.1, longitude: $0.0) }
		return ring + [ring[0]]
	}

	private func multi(_ polygons: [[[GISTools.Coordinate3D]]]) throws -> GISTools.MultiPolygon {
		let made: GISTools.MultiPolygon? = GISTools.MultiPolygon(polygons)
		return try #require(made)
	}

	/// Sizes of each regrouped polygon's rings, so the grouping reads at a glance.
	private func shape(_ groups: [[[GISTools.Coordinate3D]]]) -> [[Double]] {
		groups.map { $0.map { ($0[1].longitude - $0[0].longitude).magnitude + ($0[2].latitude - $0[1].latitude).magnitude } }
	}

	@Test func specWoundTilesGetTheirOuterRingsBack() throws {
		// Protomaps' ocean in a strait tile, as mvt-tools hands it over: three outer rings (clockwise
		// on the map, as the spec winds them) filed as one polygon, and each island a polygon of its own.
		let decoded = try multi([
			[square(0, 0, 1, clockwise: true), square(2, 0, 2, clockwise: true), square(5, 0, 4, clockwise: true)],
			[square(5.5, 0.5, 0.5)],
			[square(7, 2, 0.5)]
		])
		let groups = OfflineVectorTileProvider.polygonRings(decoded)
		#expect(shape(groups) == [[2], [4], [8, 1, 1]])
	}

	@Test func tilesMvtToolsWroteKeepTheirGrouping() throws {
		// mvt-tools' own winding: outer rings counter-clockwise, holes clockwise.
		let decoded = try multi([
			[square(0, 0, 4), square(1, 1, 1, clockwise: true)],
			[square(5, 0, 2)]
		])
		let groups = OfflineVectorTileProvider.polygonRings(decoded)
		#expect(shape(groups) == [[8, 2], [4]])
	}

	@Test func aSingleRingIsOnePolygon() throws {
		let made: GISTools.Polygon? = GISTools.Polygon([square(0, 0, 1, clockwise: true)])
		#expect(OfflineVectorTileProvider.polygonRings(try #require(made)).count == 1)
	}
}
