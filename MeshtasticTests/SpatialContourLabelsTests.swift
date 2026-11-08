//
//  SpatialContourLabelsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/7/26.
//
import CoreGraphics
import CoreLocation
import Testing
@testable import Meshtastic

@Suite("Contour elevation labels")
struct SpatialContourLabelsTests {

	private let bounds = CGRect(x: 0, y: 0, width: 2048, height: 2048)
	/// About the size the label font sets four digits.
	private func measure(_ text: String) -> CGSize { CGSize(width: CGFloat(text.count) * 10, height: 18) }

	private func line(_ elevation: Double, _ points: [CGPoint]) -> SpatialTerrainContours.CanvasLine {
		SpatialTerrainContours.CanvasLine(elevation: elevation, points: points, clip: bounds)
	}

	@Test("elevations print as plain numbers in the map's unit")
	func text() {
		#expect(SpatialTerrainContours.labelText(elevationMeters: 1000, metric: true) == "1000")
		#expect(SpatialTerrainContours.labelText(elevationMeters: 304.8, metric: false) == "1000")
		#expect(SpatialTerrainContours.labelText(elevationMeters: 3048, metric: false) == "10000")
	}

	@Test("a long straight line is labeled a spacing apart along it, and level text stays level")
	func spacingAlongALine() {
		let straight = line(500, [CGPoint(x: 50, y: 1000), CGPoint(x: 2000, y: 1000)])
		let labels = SpatialTerrainContours.placeLabels(on: [straight], metric: true, scale: 1, within: bounds, measure: measure)
		#expect(labels.count == 3)
		for (a, b) in zip(labels, labels.dropFirst()) {
			#expect(abs(b.center.x - a.center.x) >= SpatialTerrainContours.labelSpacing)
		}
		#expect(labels.allSatisfy { abs($0.angle) < 0.001 })
	}

	@Test("a line too tight to hold the number straight gets no label")
	func tightBends() {
		var zigzag: [CGPoint] = []
		for step in 0..<200 {
			zigzag.append(CGPoint(x: 100 + CGFloat(step) * 9, y: 1000 + (step.isMultiple(of: 2) ? 0 : 9)))
		}
		#expect(SpatialTerrainContours.placeLabels(on: [line(500, zigzag)], metric: true, scale: 1, within: bounds, measure: measure).isEmpty)
	}

	@Test("a straight line with the terrain's small wiggles is still labeled")
	func smallWiggles() {
		var wiggly: [CGPoint] = []
		for step in 0..<400 {
			wiggly.append(CGPoint(x: 50 + CGFloat(step) * 4.8, y: 1000 + (step.isMultiple(of: 2) ? 0 : 3)))
		}
		#expect(!SpatialTerrainContours.placeLabels(on: [line(500, wiggly)], metric: true, scale: 1, within: bounds, measure: measure).isEmpty)
	}

	@Test("lines keep their width on flat ground and narrow on slopes")
	func widthOnSlopes() {
		let bounds = GeoBounds(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1)
		let flat = SpatialTerrainContours.Relief(bounds: bounds, columns: 3, rows: 3, heights: Array(repeating: 0.1, count: 9), cellWidth: 0.1, cellDepth: 0.1)
		#expect(flat.widthFactor(at: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5)) == 1)
		// Rising 0.1 per 0.1 eastward: a 45° slope, where a texel covers √2 of ground.
		let slope = SpatialTerrainContours.Relief(bounds: bounds, columns: 3, rows: 3, heights: [0, 0.1, 0.2, 0, 0.1, 0.2, 0, 0.1, 0.2], cellWidth: 0.1, cellDepth: 0.1)
		#expect(abs(slope.widthFactor(at: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5)) - 1 / 2.0.squareRoot()) < 0.001)
	}

	@Test("labels on neighboring lines keep their distance, and their number is capped")
	func clearanceAndCap() {
		// Index lines 20 points apart: far closer than two labels may be.
		let lines = (0..<60).map { row in
			line(Double(row) * 50, [CGPoint(x: 50, y: 100 + CGFloat(row) * 20), CGPoint(x: 2000, y: 100 + CGFloat(row) * 20)])
		}
		let labels = SpatialTerrainContours.placeLabels(on: lines, metric: true, scale: 1, within: bounds, measure: measure)
		#expect(labels.count <= SpatialTerrainContours.maxLabels)
		for (index, a) in labels.enumerated() {
			for b in labels[(index + 1)...] {
				#expect(hypot(a.center.x - b.center.x, a.center.y - b.center.y) >= SpatialTerrainContours.labelClearance)
			}
		}
	}

	@Test("a line drawn right to left is still labeled to read left to right")
	func readsLeftToRight() {
		let backwards = line(500, [CGPoint(x: 2000, y: 1200), CGPoint(x: 50, y: 800)])
		let labels = SpatialTerrainContours.placeLabels(on: [backwards], metric: true, scale: 1, within: bounds, measure: measure)
		#expect(!labels.isEmpty)
		#expect(labels.allSatisfy { abs($0.angle) < .pi / 2 })
	}

	@Test("on the 2D map, the longest lines' labels win and close ones are dropped")
	func sparseOnTheFlatMap() {
		func candidate(_ id: String, lat: Double, lon: Double, points: Int) -> (pointCount: Int, label: TerrainContourLabel) {
			(points, TerrainContourLabel(id: id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), text: id))
		}
		// At zoom 12 a tile is about 0.088° of longitude, so these two are a tenth of a tile apart.
		let candidates = [
			candidate("short", lat: 47.6, lon: -122.300, points: 20),
			candidate("long", lat: 47.6, lon: -122.309, points: 200),
			candidate("far", lat: 47.6, lon: -122.200, points: 30)
		]
		let labels = TerrainContourProvider.sparseLabels(candidates, zoom: 12)
		#expect(labels.map(\.id) == ["long", "far"])
		let many = (0..<100).map { candidate("\($0)", lat: 47 + Double($0) * 0.1, lon: -122, points: 50) }
		#expect(TerrainContourProvider.sparseLabels(many, zoom: 12).count == 12)
	}
}
