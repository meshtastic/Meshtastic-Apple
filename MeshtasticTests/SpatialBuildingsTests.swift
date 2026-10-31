//
//  SpatialBuildingsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//
import CoreLocation
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map buildings")
struct SpatialBuildingsTests {

	private let circle = SpatialCircle(latitude: 47.6062, longitude: -122.3321, radiusMeters: 1_000)

	/// Flat ground at sea level under the circle.
	private func flatGeometry() -> SpatialTerrainGeometry {
		let flat = SpatialHeightGrid(columns: 2, rows: 2, heights: [0, 0, 0, 0], covered: [true, true, true, true], baseElevation: 0, maxElevation: 0)
		return SpatialTerrainGeometry(grid: flat, transform: SpatialModelTransform(frame: SpatialFrame(bounds: circle.bounds), baseElevation: 0, maxElevation: 0))
	}

	/// A square `side` meters across, centered `east` and `north` meters from the circle's center.
	private func square(side: Double, east: Double = 0, north: Double = 0, height: Double? = 20, minHeight: Double = 0) -> SpatialBuildingFootprint {
		let metersPerLon = circle.metersPerDegreeLongitude
		let metersPerLat = SpatialFrame.metersPerDegreeLatitude
		let corners: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
		let outline = corners.map { x, y in
			CLLocationCoordinate2D(latitude: circle.latitude + (north + y * side / 2) / metersPerLat, longitude: circle.longitude + (east + x * side / 2) / metersPerLon)
		}
		return SpatialBuildingFootprint(outline: outline, height: height, minHeight: minHeight)
	}

	@Test("heights are read from doubles and integers, and anything else is no height")
	func meters() {
		#expect(SpatialBuildingFootprint.meters(Double(12.5)) == 12.5)
		#expect(SpatialBuildingFootprint.meters(Int(30)) == 30)
		#expect(SpatialBuildingFootprint.meters(Int64(7)) == 7)
		#expect(SpatialBuildingFootprint.meters(Float(3)) == 3)
		#expect(SpatialBuildingFootprint.meters("40") == nil)
		#expect(SpatialBuildingFootprint.meters(nil) == nil)
	}

	@Test("an L-shaped roof fills exactly its own area, with every triangle the outline's way round")
	func concaveRoof() {
		let l: [SIMD2<Float>] = [[0, 0], [2, 0], [2, 1], [1, 1], [1, 2], [0, 2]]
		#expect(SpatialBuildings.signedArea(l) > 0)
		let indices = SpatialBuildings.triangulate(l)
		#expect(indices.count == (l.count - 2) * 3)
		var area: Float = 0
		for t in stride(from: 0, to: indices.count, by: 3) {
			let tri = [l[Int(indices[t])], l[Int(indices[t + 1])], l[Int(indices[t + 2])]]
			let twice = SpatialBuildings.signedArea(tri)
			#expect(twice > 0)
			area += twice
		}
		#expect(abs(area - SpatialBuildings.signedArea(l)) < 1e-5)
	}

	@Test("a closing corner and repeated corners are dropped")
	func outlineCleanup() {
		let ring: [SIMD2<Float>] = [[0, 0], [1, 0], [1, 0], [1, 1], [0, 0]]
		#expect(SpatialBuildings.outline(ring) == [[0, 0], [1, 0], [1, 1]])
	}

	@Test("every face winds the way its normal points, and nothing faces down")
	func winding() {
		// Clockwise on purpose: the mesh turns it round.
		var building = square(side: 40)
		building = SpatialBuildingFootprint(outline: building.outline.reversed(), height: 20, minHeight: 0)
		let mesh = SpatialBuildings.mesh([building, square(side: 30, east: 200)], geometry: flatGeometry())
		#expect(mesh.triangleCount == 2 * (2 * 4 + 2))
		for t in 0..<mesh.triangleCount {
			let i = (0..<3).map { Int(mesh.indices[3 * t + $0]) }
			let p = i.map { mesh.positions[$0] }
			let face = simd_cross(p[1] - p[0], p[2] - p[0])
			#expect(simd_dot(face, mesh.normals[i[0]]) > 0, "triangle \(t)")
			#expect(mesh.normals[i[0]].y >= 0)
		}
	}

	@Test("a building stands on the ground and rises at the terrain's height scale")
	func heights() throws {
		let geometry = flatGeometry()
		let transform = geometry.transform
		let scale = Float(transform.verticalExaggeration * transform.scale)
		let tower = SpatialBuildings.mesh([square(side: 40, height: 100)], geometry: geometry)
		#expect(abs(try #require(tower.positions.map(\.y).max()) - 100 * scale) < 1e-6)
		#expect(abs(try #require(tower.positions.map(\.y).min())) < 1e-6)
		let untagged = SpatialBuildings.mesh([square(side: 40, height: nil)], geometry: geometry)
		#expect(abs(try #require(untagged.positions.map(\.y).max()) - Float(SpatialBuildings.defaultHeight) * scale) < 1e-6)
		let upper = SpatialBuildings.mesh([square(side: 40, height: 100, minHeight: 60)], geometry: geometry)
		#expect(abs(try #require(upper.positions.map(\.y).min()) - 60 * scale) < 1e-6)
	}

	@Test("buildings past the edge of the round map are left out")
	func diskEdge() {
		let mesh = SpatialBuildings.mesh([square(side: 40), square(side: 40, east: 990)], geometry: flatGeometry())
		#expect(mesh.triangleCount == 2 * 4 + 2)
		// Middle inside the edge, outer corners past it.
		let straddling = SpatialBuildings.mesh([square(side: 40, east: 965)], geometry: flatGeometry())
		#expect(straddling.triangleCount == 0)
	}

	@Test("over the budget, the biggest buildings are kept")
	func budget() {
		let small = square(side: 10, east: -300)
		let big = square(side: 60, east: 300)
		let mesh = SpatialBuildings.mesh([small, big], geometry: flatGeometry(), triangleBudget: 10)
		#expect(mesh.triangleCount == 10)
		#expect(mesh.positions.allSatisfy { $0.x > 0 })
	}

	@Test("decodes the deepest zoom the box and the archive allow, and gives up past zoom 13")
	func zoom() {
		let town = circle.bounds
		#expect(SpatialBuildings.zoom(bounds: town, archiveMaxZoom: 15) == 15)
		#expect(SpatialBuildings.zoom(bounds: town, archiveMaxZoom: 13) == 13)
		#expect(SpatialBuildings.zoom(bounds: town, archiveMaxZoom: 12) == nil)
		let region = SpatialCircle(latitude: 47.6, longitude: -122.3, radiusMeters: 60_000).bounds
		#expect(SpatialBuildings.zoom(bounds: region, archiveMaxZoom: 15) == nil)
	}
}
