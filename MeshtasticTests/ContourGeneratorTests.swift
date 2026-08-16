//
//  ContourGeneratorTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/15/26.
//
//  Marching-squares contour generation over synthetic elevation tiles:
//  flat, cone, inclined plane, saddle, plus the zoom interval table.
//

import Testing
import Foundation
import CoreGraphics
@testable import Meshtastic

@Suite
struct ContourGeneratorTests {

	/// Builds a synthetic tile; the closure receives tile-local sample
	/// coordinates including the margin ring (-margin..<size+margin).
	private func makeTile(size: Int = 64, margin: Int = 2, elevation: (Int, Int) -> Float) -> ElevationTile {
		let gridSize = size + 2 * margin
		var elevations = [Float](repeating: 0, count: gridSize * gridSize)
		for gridY in 0..<gridSize {
			for gridX in 0..<gridSize {
				elevations[gridY * gridSize + gridX] = elevation(gridX - margin, gridY - margin)
			}
		}
		return ElevationTile(z: 12, x: 0, y: 0, size: size, margin: margin, elevations: elevations)
	}

	private let intervals = ContourIntervals(minor: 100, index: 500)

	// MARK: - Flat

	@Test func flatTile_hasNoContours() {
		let tile = makeTile { _, _ in 0 }
		#expect(ContourGenerator.contours(tile: tile, intervals: intervals).isEmpty)
	}

	// MARK: - Cone

	/// Cone: 500 m peak at the tile center dropping 20 m per sample, resting on
	/// a 50 m plateau. Crossing levels are 100/200/300/400 with ring radii
	/// 20/15/10/5 samples — all inside the tile.
	// Pins the saddle disambiguation rule: high corners NW+SE with a low cell
	// center must isolate each high corner (top edge pairs with left, bottom with
	// right). Swapping the rule's branches pairs the opposite edges and fails.
	@Test func saddleRule_lowCenterIsolatesHighCorners() {
		let tile = makeTile(size: 2, margin: 0) { x, y in
			(x == 0 && y == 0) || (x == 1 && y == 1) ? 10 : 2
		}
		let lines = ContourGenerator.contours(tile: tile, intervals: ContourIntervals(minor: 6, index: 30))
		#expect(lines.count == 2)
		for line in lines {
			let touchesTop = line.points.contains { $0.y <= 0.01 }
			let touchesLeft = line.points.contains { $0.x <= 0.01 }
			let touchesBottom = line.points.contains { $0.y >= 0.49 }
			let touchesRight = line.points.contains { $0.x >= 0.49 }
			if touchesTop {
				#expect(touchesLeft && !touchesRight)
			}
			if touchesBottom {
				#expect(touchesRight && !touchesLeft)
			}
		}
	}

	private func coneTile() -> ElevationTile {
		makeTile { gridX, gridY in
			let dx = Double(gridX) - 32
			let dy = Double(gridY) - 32
			return Float(max(500 - 20 * (dx * dx + dy * dy).squareRoot(), 50))
		}
	}

	@Test func cone_producesOneClosedRingPerLevel() {
		let lines = ContourGenerator.contours(tile: coneTile(), intervals: intervals)
		#expect(lines.count == 4)
		#expect(Set(lines.map(\.elevation)) == [100, 200, 300, 400])
		for line in lines {
			#expect(line.points.count > 4)
			#expect(line.points.first == line.points.last, "ring at \(line.elevation) m should close")
		}
	}

	@Test func cone_ringsAreNestedAroundTheCenter() {
		let lines = ContourGenerator.contours(tile: coneTile(), intervals: intervals)
			.sorted { $0.elevation < $1.elevation }
		let radii = lines.map { line in
			line.points.map { point in
				let dx = point.x - 0.5
				let dy = point.y - 0.5
				return (dx * dx + dy * dy).squareRoot()
			}.max() ?? 0
		}
		for (index, line) in lines.enumerated() {
			let expected = (500 - line.elevation) / 20 / 64 // ring radius in tile units
			#expect(abs(radii[index] - expected) < 1.0 / 64)
			if index > 0 {
				#expect(radii[index] < radii[index - 1], "higher level should nest inside lower")
			}
		}
	}

	// MARK: - Inclined plane

	@Test func inclinedPlane_producesParallelLinesSpanningTheTile() {
		// 10 m per sample along x: positive levels 100...600 cross inside the grid
		// (level 0 is excluded — sea level never draws a contour).
		let tile = makeTile { gridX, _ in Float(10 * gridX) }
		let lines = ContourGenerator.contours(tile: tile, intervals: intervals)
		#expect(lines.count == 6)
		#expect(lines.map(\.elevation).sorted() == [100, 200, 300, 400, 500, 600])
		for line in lines {
			let xValues = line.points.map(\.x)
			let yValues = line.points.map(\.y)
			// Straight and vertical: constant x at elevation/640 tile units.
			let expectedX = line.elevation / 640
			#expect(xValues.allSatisfy { abs($0 - expectedX) < 1e-9 })
			// Runs through the margin past both tile edges.
			#expect(yValues.min() ?? 1 <= 0)
			#expect(yValues.max() ?? 0 >= 1)
		}
	}

	// MARK: - Saddle

	@Test func saddle_producesSanePolylines() {
		// z = x·y + 300 about the cell-centered saddle point (31.5, 31.5); the
		// 300 m contour crosses saddle cells and exercises the midpoint-average
		// rule (offset keeps the saddle level positive — sea level never draws).
		let tile = makeTile { gridX, gridY in
			Float((Double(gridX) - 31.5) * (Double(gridY) - 31.5) + 300)
		}
		let lines = ContourGenerator.contours(tile: tile, intervals: intervals)
		#expect(!lines.isEmpty)
		#expect(lines.contains { $0.elevation == 300 })
		for line in lines {
			#expect(line.points.count >= 2)
			#expect(line.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
		}
	}

	// MARK: - Interval table

	@Test func intervalTable_matchesSpecForAllZoomBands() {
		let foot = 0.3048
		let cases: [(zoom: Int, metric: (Double, Double), imperial: (Double, Double))] = [
			(8, (500, 2500), (2000 * foot, 10000 * foot)),
			(10, (500, 2500), (2000 * foot, 10000 * foot)),
			(11, (100, 500), (500 * foot, 2500 * foot)),
			(12, (100, 500), (500 * foot, 2500 * foot)),
			(13, (50, 250), (200 * foot, 1000 * foot)),
			(14, (50, 250), (200 * foot, 1000 * foot)),
			(15, (20, 100), (100 * foot, 500 * foot)),
			(18, (20, 100), (100 * foot, 500 * foot))
		]
		for testCase in cases {
			let metric = ContourIntervals.intervals(forZoom: testCase.zoom, metric: true)
			#expect(metric.minor == testCase.metric.0, "zoom \(testCase.zoom) metric minor")
			#expect(metric.index == testCase.metric.1, "zoom \(testCase.zoom) metric index")
			let imperial = ContourIntervals.intervals(forZoom: testCase.zoom, metric: false)
			#expect(abs(imperial.minor - testCase.imperial.0) < 1e-9, "zoom \(testCase.zoom) imperial minor")
			#expect(abs(imperial.index - testCase.imperial.1) < 1e-9, "zoom \(testCase.zoom) imperial index")
		}
	}

	// MARK: - Index flagging

	@Test func indexContours_flaggedOnIndexMultiplesOnly() {
		let tile = makeTile { gridX, _ in Float(10 * gridX) }
		let lines = ContourGenerator.contours(tile: tile, intervals: intervals)
		let line500 = lines.first { $0.elevation == 500 }
		let line400 = lines.first { $0.elevation == 400 }
		#expect(line500?.isIndex == true)
		#expect(line400?.isIndex == false)
	}
}
