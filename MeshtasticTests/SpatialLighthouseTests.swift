//
//  SpatialLighthouseTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map lighthouse")
struct SpatialLighthouseTests {

	@Test("the lighthouse stays within its triangle budget, stands on the ground and tops out at its height")
	func meshShape() throws {
		let parts = SpatialLighthouse.geometry()
		#expect(Set(parts.keys) == Set(SpatialLighthouse.Part.allCases))
		let total = parts.values.map(\.triangleCount).reduce(0, +)
		#expect(total > 200 && total < SpatialLighthouse.triangleBudget, "\(total)")
		let ys = parts.values.flatMap { $0.positions.map(\.y) }
		#expect(try #require(ys.min()) >= -0.0001)
		#expect(try #require(ys.min()) < 0.0001)
		#expect(abs(try #require(ys.max()) - SpatialLighthouse.height) < 0.0003)
		for (part, mesh) in parts {
			#expect(mesh.triangleCount > 0, "\(part)")
			#expect(mesh.positions.count == mesh.normals.count, "\(part)")
			#expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count }, "\(part)")
			#expect(mesh.normals.allSatisfy { !$0.x.isNaN && abs(simd_length($0) - 1) < 0.001 }, "\(part)")
		}
	}

	@Test("every face winds the way its normals point")
	func winding() {
		for (part, mesh) in SpatialLighthouse.geometry() {
			var facing = true
			for t in 0..<mesh.triangleCount {
				let i = (0..<3).map { Int(mesh.indices[3 * t + $0]) }
				let p = i.map { mesh.positions[$0] }
				let face = simd_cross(p[1] - p[0], p[2] - p[0])
				let normal = i.map { mesh.normals[$0] }.reduce(SIMD3<Float>.zero, +)
				if simd_dot(face, normal) <= 0 { facing = false }
			}
			#expect(facing, "\(part)")
		}
	}

	@Test("taller than the fire lookout and about as wide as its cab, so it doesn't look tiny beside it")
	func lookoutSized() throws {
		#expect(SpatialLighthouse.height > SpatialLookout.height * 1.3)
		let xs = SpatialLighthouse.geometry().values.flatMap { $0.positions.map(\.x) }
		let half = max(abs(try #require(xs.min())), try #require(xs.max()))
		#expect(half >= SpatialLookout.cabHalf && half <= SpatialLookout.deckHalf * 1.4)
	}

	@Test("the door and windows are on the back, away from the lantern's front")
	func openingsAtTheBack() throws {
		let opening = try #require(SpatialLighthouse.geometry()[.opening])
		#expect(opening.positions.allSatisfy { $0.z < 0 })
	}
}

@Suite("Lighthouse coast finder")
struct LookoutCoastTests {
	static let size = 60
	static let cell = 250.0

	/// A grid of `size` cells a side, land where `land` says at `height`, sea elsewhere.
	static func grid(height: Float = 30, land: (Int, Int) -> Bool) -> [Float] {
		(0..<size * size).map { land($0 % size, $0 / size) ? height : 0 }
	}

	static func candidates(_ heights: [Float], covered: [Bool]? = nil) -> [LookoutCoast.Candidate] {
		LookoutCoast.candidates(in: LookoutCoast.Grid(heights: heights, covered: covered ?? Array(repeating: true, count: heights.count), columns: size, rows: size, cellWidth: cell, cellHeight: cell))
	}

	static func angle(_ a: Double, _ b: Double) -> Double {
		abs((a - b + 540).truncatingRemainder(dividingBy: 360) - 180)
	}

	@Test("a straight shore with the sea to the east faces east, from the land at the water's edge")
	func straightShore() throws {
		let found = Self.candidates(Self.grid { column, _ in column < 30 })
		let best = try #require(found.first)
		#expect(best.index % Self.size >= 30 - LookoutCoast.shoreCells)
		#expect(best.index % Self.size < 30)
		#expect(Self.angle(best.facing, 90) <= 360 / Double(LookoutCoast.bearings))
		// Land well back from the shore isn't a candidate.
		#expect(found.allSatisfy { $0.index % Self.size >= 30 - LookoutCoast.shoreCells })
	}

	@Test("the tip of a headland reaching north looks out on more water than its sides, and faces north")
	func headlandTip() throws {
		// A coast along the south, and a headland four cells wide reaching north from it to row 20.
		let heights = Self.grid { column, row in row >= 50 || (row >= 20 && (28...31).contains(column)) }
		let best = try #require(Self.candidates(heights).first)
		#expect(best.index / Self.size <= 22)
		#expect((27...32).contains(best.index % Self.size))
		#expect(Self.angle(best.facing, 0) <= 360 / Double(LookoutCoast.bearings) * 2)
		#expect(best.openBearings > LookoutCoast.bearings / 2)
	}

	@Test("on equal water, the higher headland ranks first")
	func higherFirst() throws {
		var heights = Self.grid { column, _ in column < 30 }
		let low = 30 * Self.size + 29
		let high = 10 * Self.size + 29
		heights[high] = 90
		let found = Self.candidates(heights)
		let highRank = try #require(found.firstIndex { $0.index == high })
		let lowRank = try #require(found.firstIndex { $0.index == low })
		#expect(highRank < lowRank)
	}

	@Test("no sea, no land, or sea the terrain doesn't cover gives no candidates")
	func nothingToStandOn() {
		#expect(Self.candidates(Self.grid { _, _ in true }).isEmpty)
		#expect(Self.candidates(Self.grid { _, _ in false }).isEmpty)
		let heights = Self.grid { column, _ in column < 30 }
		let covered = (0..<heights.count).map { $0 % Self.size < 30 }
		#expect(Self.candidates(heights, covered: covered).isEmpty)
	}

	@Test("a bay's shore doesn't count the land across the water as open sea")
	func narrowInlet() {
		// A channel three cells wide between two shores: never 90% sea out to the reach.
		let heights = Self.grid { column, _ in !(29...31).contains(column) }
		#expect(Self.candidates(heights).isEmpty)
	}

	@Test("the facing is the middle of the widest run of open water, going round past north")
	func facingRuns() {
		var open = Array(repeating: false, count: 32)
		for index in [30, 31, 0, 1, 2] { open[index] = true }
		#expect(LookoutCoast.facing(open) == 0)
		open = Array(repeating: false, count: 32)
		for index in 4...12 { open[index] = true }
		for index in 20...21 { open[index] = true }
		#expect(LookoutCoast.facing(open) == 90)
		#expect(LookoutCoast.facing(Array(repeating: true, count: 32)) == 0)
	}

	@Test("the lighthouse keeps its own site and turn, apart from the lookout's")
	func keptApart() {
		#expect(LookoutSiteKind.coast.siteKey != LookoutSiteKind.summit.siteKey)
		#expect(LookoutSiteKind.coast.turnsKey != LookoutSiteKind.summit.turnsKey)
		#expect(LookoutSiteKind.summit.turnsKey == SpatialLookout.turnsKey)
		#expect(LookoutSiteKind.summit.standHeight == 34)
	}
}
