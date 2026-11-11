//
//  SpatialRooftopTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import CoreLocation
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map city rooftop")
struct SpatialRooftopTests {

	private let circle = SpatialCircle(latitude: 47.6062, longitude: -122.3321, radiusMeters: 1_000)

	/// Flat ground at sea level under the circle.
	private func flatGeometry() -> SpatialTerrainGeometry {
		let flat = SpatialHeightGrid(columns: 2, rows: 2, heights: [0, 0, 0, 0], covered: [true, true, true, true], baseElevation: 0, maxElevation: 0)
		return SpatialTerrainGeometry(grid: flat, transform: SpatialModelTransform(frame: SpatialFrame(bounds: circle.bounds), baseElevation: 0, maxElevation: 0))
	}

	/// A square `side` meters across, centered `east` meters from the circle's center.
	private func square(side: Double, east: Double = 0, height: Double) -> SpatialBuildingFootprint {
		let metersPerLon = circle.metersPerDegreeLongitude
		let metersPerLat = SpatialFrame.metersPerDegreeLatitude
		let corners: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
		let outline = corners.map { x, y in
			CLLocationCoordinate2D(latitude: circle.latitude + (y * side / 2) / metersPerLat, longitude: circle.longitude + (east + x * side / 2) / metersPerLon)
		}
		return SpatialBuildingFootprint(outline: outline, height: height, minHeight: 0)
	}

	@Test("the water tower and mast stay within their budget, stand from the roof and top out at their height")
	func meshShape() throws {
		let parts = SpatialRooftop.geometry()
		#expect(Set(parts.keys) == Set(SpatialRooftop.Part.allCases))
		let total = parts.values.map(\.triangleCount).reduce(0, +)
		#expect(total > 100 && total < SpatialRooftop.triangleBudget, "\(total)")
		let ys = parts.values.flatMap { $0.positions.map(\.y) }
		#expect(abs(try #require(ys.min())) < 0.0002 * SpatialRooftop.scale)
		#expect(abs(try #require(ys.max()) - SpatialRooftop.height) < 0.0003 * SpatialRooftop.scale)
		for (part, mesh) in parts {
			#expect(mesh.triangleCount > 0, "\(part)")
			#expect(mesh.positions.count == mesh.normals.count, "\(part)")
			#expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count }, "\(part)")
		}
	}

	@Test("it stands on the roof's top, not buried in the building or floating over it, and on the ground off any roof")
	func standsAtRoofHeight() throws {
		let geometry = flatGeometry()
		let transform = geometry.transform
		let scale = Float(transform.verticalExaggeration * transform.scale)
		let roofs = SpatialBuildings.build([square(side: 40, height: 180), square(side: 30, east: 300, height: 25)], geometry: geometry, revision: 1).roofs
		func point(east: Double) -> SIMD2<Float> {
			let p = transform.position(CLLocationCoordinate2D(latitude: circle.latitude, longitude: circle.longitude + east / circle.metersPerDegreeLongitude), altitude: 0)
			return SIMD2(p.x, p.z)
		}
		let tower = try #require(roofs.top(at: point(east: 0)))
		#expect(abs(roofs.standHeight(at: point(east: 0), ground: 0) - tower) < 1e-6)
		#expect(abs(tower - 180 * scale) < 1e-5)
		#expect(abs(roofs.standHeight(at: point(east: 300), ground: 0) - 25 * scale) < 1e-5)
		#expect(roofs.standHeight(at: point(east: 600), ground: 0.004) == 0.004)
	}
}
