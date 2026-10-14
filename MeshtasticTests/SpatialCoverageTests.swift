//
//  SpatialCoverageTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import CoreGraphics
import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

@Suite("Spatial map coverage")
struct SpatialCoverageTests {
	let box = GeoBounds(minLon: -122.40, minLat: 47.55, maxLon: -122.30, maxLat: 47.65)
	let center = CLLocationCoordinate2D(latitude: 47.60, longitude: -122.35)
	let size = CGSize(width: 64, height: 64)

	// MARK: Helpers

	private func square(_ c: CLLocationCoordinate2D, halfDegrees d: Double) -> [CLLocationCoordinate2D] {
		[
			CLLocationCoordinate2D(latitude: c.latitude - d, longitude: c.longitude - d),
			CLLocationCoordinate2D(latitude: c.latitude - d, longitude: c.longitude + d),
			CLLocationCoordinate2D(latitude: c.latitude + d, longitude: c.longitude + d),
			CLLocationCoordinate2D(latitude: c.latitude + d, longitude: c.longitude - d),
			CLLocationCoordinate2D(latitude: c.latitude - d, longitude: c.longitude - d)
		]
	}

	private func estimate(
		node: Int64? = 1, range: Double? = 3_000, bands: [SpatialCoverageBand],
		bounds: GeoBounds? = nil, created: Date = Date()
	) -> SpatialCoverageEstimate {
		SpatialCoverageEstimate(
			id: UUID(), nodeNum: node, transmitter: center, rangeMeters: range,
			bounds: bounds ?? box, created: created, bands: bands
		)
	}

	private func band(_ dbm: Double?, _ rgba: SIMD4<Double>, _ polygons: [SpatialCoveragePolygon], label: String? = nil) -> SpatialCoverageBand {
		SpatialCoverageBand(dbm: dbm, label: label, rgba: rgba, polygons: polygons)
	}

	/// RGBA bytes of a pixel, rows counted from the top of the image.
	private func pixel(_ image: CGImage, x: Int, y: Int) -> SIMD4<Int> {
		var bytes = [UInt8](repeating: 0, count: 4)
		let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
								space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
		return SIMD4(Int(bytes[0]), Int(bytes[1]), Int(bytes[2]), Int(bytes[3]))
	}

	/// The image pixel a coordinate lands on.
	private func pixel(_ image: CGImage, at coordinate: CLLocationCoordinate2D, frame: SpatialFrame) -> SIMD4<Int> {
		let p = SpatialTextureRenderer.canvasPoint(coordinate, frame: frame, size: size)
		return pixel(image, x: min(Int(p.x), image.width - 1), y: min(image.height - 1 - Int(p.y), image.height - 1))
	}

	private func east(_ meters: Double) -> CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + meters / (SpatialFrame.metersPerDegreeLatitude * cos(center.latitude * .pi / 180)))
	}

	// MARK: Mapping

	@Test func boundsCornersLandOnTheCanvasCorners() {
		let frame = SpatialFrame(bounds: box)
		let northWest = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: box.maxLat, longitude: box.minLon), frame: frame, size: size)
		let southEast = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: box.minLat, longitude: box.maxLon), frame: frame, size: size)
		// CoreGraphics counts y from the bottom, so north is at the top: y = height.
		#expect(abs(northWest.x) < 1e-6 && abs(northWest.y - 64) < 1e-6)
		#expect(abs(southEast.x - 64) < 1e-6 && abs(southEast.y) < 1e-6)
	}

	@Test func canvasPointsMatchTheTerrainTextureCoordinates() {
		let frame = SpatialFrame(bounds: box)
		let grid = SpatialHeightGrid(columns: 2, rows: 2, heights: [0, 0, 0, 0], covered: [false, false, false, false], baseElevation: 0, maxElevation: 0)
		let geometry = SpatialTerrainGeometry(grid: grid, transform: SpatialModelTransform(frame: frame, baseElevation: 0, maxElevation: 0))
		// Vertices well inside the disk keep their grid coordinate.
		for (i, j) in [(geometry.columns / 2, geometry.rows / 2), (geometry.columns / 3, geometry.rows / 2 + 5)] {
			let latitude = box.maxLat - (box.maxLat - box.minLat) * Double(j) / Double(geometry.rows - 1)
			let longitude = box.minLon + (box.maxLon - box.minLon) * Double(i) / Double(geometry.columns - 1)
			let p = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), frame: frame, size: size)
			let uv = geometry.textureCoordinates[j * geometry.columns + i]
			// RealityKit's v runs up from the bottom of the image, the same way CoreGraphics' y does.
			#expect(abs(Float(p.x / size.width) - uv.x) < 1e-4)
			#expect(abs(Float(p.y / size.height) - uv.y) < 1e-4)
		}
	}

	// MARK: Render

	@Test func bandIsOpaqueInsideAndShadowFillsTheRestOfTheRange() throws {
		let frame = SpatialFrame(bounds: box)
		let blue = SIMD4<Double>(0, 0, 1, 1)
		let estimate = estimate(bands: [band(-100, blue, [SpatialCoveragePolygon(outer: square(center, halfDegrees: 0.01), holes: [])])])
		let image = try #require(SpatialCoverageTexture.render([estimate], frame: frame, size: size))
		let inside = pixel(image, at: center, frame: frame)
		#expect(inside == SIMD4(0, 0, 255, 255))
		let shadow = pixel(image, at: east(2_000), frame: frame)
		#expect(shadow.x == 0 && shadow.y == 0 && shadow.z == 0)
		#expect(abs(shadow.w - 115) <= 2)
		// The corner of the box is past the 3 km range.
		#expect(pixel(image, x: 0, y: 0).w == 0)
		#expect(pixel(image, x: 63, y: 63).w == 0)
	}

	@Test func holesStayShadow() throws {
		let frame = SpatialFrame(bounds: box)
		let polygon = SpatialCoveragePolygon(outer: square(center, halfDegrees: 0.015), holes: [square(center, halfDegrees: 0.005)])
		let image = try #require(SpatialCoverageTexture.render([estimate(bands: [band(-100, SIMD4(1, 0, 0, 1), [polygon])])], frame: frame, size: size))
		let hole = pixel(image, at: center, frame: frame)
		#expect(hole.x == 0 && abs(hole.w - 115) <= 2)
		let ring = pixel(image, at: CLLocationCoordinate2D(latitude: center.latitude + 0.01, longitude: center.longitude), frame: frame)
		#expect(ring == SIMD4(255, 0, 0, 255))
	}

	@Test func noRangeMeansNoShadow() throws {
		let frame = SpatialFrame(bounds: box)
		let polygon = SpatialCoveragePolygon(outer: square(center, halfDegrees: 0.01), holes: [])
		let image = try #require(SpatialCoverageTexture.render([estimate(range: nil, bands: [band(-100, SIMD4(1, 0, 0, 1), [polygon])])], frame: frame, size: size))
		#expect(pixel(image, at: east(2_000), frame: frame).w == 0)
	}

	@Test func strongerBandPaintsOverWeaker() throws {
		let frame = SpatialFrame(bounds: box)
		let weak = band(-120, SIMD4(1, 0, 0, 1), [SpatialCoveragePolygon(outer: square(center, halfDegrees: 0.02), holes: [])])
		let strong = band(-90, SIMD4(0, 0, 1, 1), [SpatialCoveragePolygon(outer: square(center, halfDegrees: 0.008), holes: [])])
		let image = try #require(SpatialCoverageTexture.render([estimate(bands: [weak, strong])], frame: frame, size: size))
		#expect(pixel(image, at: center, frame: frame) == SIMD4(0, 0, 255, 255))
		#expect(pixel(image, at: CLLocationCoordinate2D(latitude: center.latitude + 0.014, longitude: center.longitude), frame: frame) == SIMD4(255, 0, 0, 255))
	}

	@Test func nothingToDrawGivesNoImage() {
		#expect(SpatialCoverageTexture.render([], frame: SpatialFrame(bounds: box), size: size) == nil)
	}

	@Test func rangeRingIsRoundAndClosed() {
		let ring = SpatialCoverageTexture.rangeRing(center: center, radiusMeters: 5_000, segments: 64)
		#expect(ring.count == 65)
		#expect(ring.first!.latitude == ring.last!.latitude && ring.first!.longitude == ring.last!.longitude)
		let circle = SpatialCircle(latitude: center.latitude, longitude: center.longitude, radiusMeters: 0)
		for point in ring {
			#expect(abs(circle.distanceMeters(to: point) - 5_000) < 25)
		}
	}

	// MARK: Overlay mesh

	@Test func overlaySurfaceIsTheRaisedSurfaceWithoutTheSkirt() {
		let frame = SpatialFrame(bounds: box)
		let grid = SpatialHeightGrid(columns: 3, rows: 3, heights: [0, 50, 0, 50, 200, 50, 0, 50, 0], covered: Array(repeating: true, count: 9), baseElevation: 0, maxElevation: 200)
		let geometry = SpatialTerrainGeometry(grid: grid, transform: SpatialModelTransform(frame: frame, baseElevation: 0, maxElevation: 200))
		let count = geometry.columns * geometry.rows
		#expect(geometry.positions.count > count, "the terrain has a skirt to leave out")
		let overlay = geometry.overlaySurface(lift: 0.003)
		#expect(overlay.positions.count == count)
		#expect(overlay.uvs.count == count && overlay.normals.count == count)
		#expect(overlay.indices.count == geometry.surfaceTriangleCount * 3)
		#expect(overlay.indices.allSatisfy { Int($0) < count })
		for index in stride(from: 0, to: count, by: 37) {
			#expect(abs(overlay.positions[index].y - (geometry.positions[index].y + 0.003)) < 1e-6)
			#expect(overlay.uvs[index] == geometry.textureCoordinates[index])
		}
	}

	// MARK: Parser

	private let collectionJSON = """
	{ "type": "FeatureCollection", "features": [
		{ "type": "Feature",
		  "geometry": { "type": "MultiPolygon", "coordinates": [
			[[[-122.40, 47.60], [-122.30, 47.60], [-122.30, 47.70], [-122.40, 47.70], [-122.40, 47.60]],
			 [[-122.36, 47.64], [-122.34, 47.64], [-122.34, 47.66], [-122.36, 47.66], [-122.36, 47.64]]],
			[[[-122.20, 47.60], [-122.10, 47.60], [-122.10, 47.70], [-122.20, 47.60]]]
		  ] },
		  "properties": { "dbm": -110, "color": "rgb(0, 128, 255)", "label": "≥ -110 dBm", "fill": "#ff0000" } },
		{ "type": "Feature",
		  "geometry": { "type": "Polygon", "coordinates": [[[-122.38, 47.62], [-122.32, 47.62], [-122.32, 47.68], [-122.38, 47.62]]] },
		  "properties": { "dbm": -80, "color": "rgb(0, 255, 0)" } },
		{ "type": "Feature",
		  "geometry": { "type": "Polygon", "coordinates": [[[-122.37, 47.63], [-122.33, 47.63], [-122.33, 47.67], [-122.37, 47.63]]] },
		  "properties": { "stroke": "#0000ff" } },
		{ "type": "Feature", "geometry": { "type": "Point", "coordinates": [-122.35, 47.65] }, "properties": {} }
	]}
	"""

	private func metadata(_ coverage: SitePlannerCoverageInfo?) -> MapDataMetadata {
		MapDataMetadata(filename: "c.geojson", originalName: "c", uploadDate: Date(timeIntervalSince1970: 1_000), fileSize: 1,
						format: "geojson", license: nil, attribution: nil, overlayCount: 4, isActive: true,
						source: .sitePlanner, coverage: coverage)
	}

	@Test func parsesPolygonsHolesColorsAndOrder() throws {
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: Data(collectionJSON.utf8))
		let info = SitePlannerCoverageInfo(nodeNum: 7, latitude: 47.65, longitude: -122.35, maxRangeKm: 20, txHeightMeters: 3, colorScale: "mesh", bounds: nil)
		let estimate = try #require(SpatialCoverageParser.estimate(collection: collection, metadata: metadata(info)))
		#expect(estimate.nodeNum == 7)
		#expect(estimate.rangeMeters == 20_000)
		#expect(estimate.transmitter.latitude == 47.65)
		// The point has no area; the band without a level sorts first.
		#expect(estimate.bands.count == 3)
		#expect(estimate.bands.map(\.dbm) == [nil, -110, -80])
		let multi = estimate.bands[1]
		#expect(multi.polygons.count == 2)
		#expect(multi.polygons[0].holes.count == 1)
		#expect(multi.label == "≥ -110 dBm")
		// fill wins over color, color over stroke, stroke when it's all there is.
		#expect(abs(multi.rgba.x - 1) < 0.01 && multi.rgba.z < 0.01)
		#expect(abs(estimate.bands[2].rgba.y - 1) < 0.01)
		#expect(abs(estimate.bands[0].rgba.z - 1) < 0.01)
		// No saved bounds: the extent of the polygons.
		#expect(estimate.bounds == GeoBounds(minLon: -122.40, minLat: 47.60, maxLon: -122.10, maxLat: 47.70))
	}

	@Test func olderFilesGetTheirCenterAndNoRange() throws {
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: Data(collectionJSON.utf8))
		let estimate = try #require(SpatialCoverageParser.estimate(collection: collection, metadata: metadata(nil)))
		#expect(estimate.nodeNum == nil)
		#expect(estimate.rangeMeters == nil)
		#expect(abs(estimate.transmitter.longitude - -122.25) < 1e-9)
		#expect(abs(estimate.transmitter.latitude - 47.65) < 1e-9)
	}

	// MARK: Visibility

	@Test func visibilityFollowsTheMode() {
		let mine = estimate(node: 1, bands: [])
		let theirs = estimate(node: 2, bands: [])
		let older = estimate(node: nil, range: nil, bands: [])
		let far = estimate(node: 1, bands: [], bounds: GeoBounds(minLon: 10, minLat: 10, maxLon: 11, maxLat: 11))
		let all = [mine, theirs, older, far]
		#expect(SpatialCoverageVisibility.visible(all, mode: .off, selected: 1, box: box).isEmpty)
		#expect(SpatialCoverageVisibility.visible(all, mode: .selected, selected: 1, box: box).map(\.id) == [mine.id])
		#expect(SpatialCoverageVisibility.visible(all, mode: .selected, selected: nil, box: box).isEmpty)
		#expect(SpatialCoverageVisibility.visible(all, mode: .all, selected: nil, box: box).map(\.id) == [mine.id, theirs.id, older.id])
	}

	// MARK: Legend

	@Test func legendIsUniqueAndStrongestFirst() {
		let a = estimate(bands: [band(-110, SIMD4(1, 0, 0, 1), [], label: "≥ -110 dBm"), band(-90, SIMD4(0, 1, 0, 1), [])])
		let b = estimate(bands: [band(-110, SIMD4(0, 0, 1, 1), []), band(nil, SIMD4(1, 1, 1, 1), []), band(-100, SIMD4(0, 0, 1, 1), [])])
		let entries = SpatialCoverageLegend.entries([a, b])
		#expect(entries.map(\.dbm) == [-90, -100, -110])
		#expect(entries.last?.label == "≥ -110 dBm")
		#expect(entries.first?.label == "≥ -90 dBm")
	}
}
