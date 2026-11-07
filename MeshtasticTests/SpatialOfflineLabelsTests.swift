//
//  SpatialOfflineLabelsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//
import CoreGraphics
import CoreLocation
import Foundation
import GISTools
import MVTTools
import Testing
import UIKit
@testable import Meshtastic

@Suite("Offline map labels")
struct SpatialOfflineLabelsTests {

	/// About 30 km around Seattle.
	private let box = GeoBounds(minLon: -122.5, minLat: 47.45, maxLon: -122.1, maxLat: 47.75)
	private let size = CGSize(width: 2048, height: 2048)

	private func label(_ name: String, _ kind: OfflineMapLabel.Kind, lat: Double = 47.6, lon: Double = -122.3, minZoom: Double = 8, rank: Int = 5) -> OfflineMapLabel {
		OfflineMapLabel(name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), kind: kind, minZoom: minZoom, rank: rank)
	}

	@Test("places map to label kinds, and countries are left out")
	func placeKinds() {
		#expect(OfflineVectorTileProvider.placeKind(kind: "locality", kindDetail: "city") == .city)
		#expect(OfflineVectorTileProvider.placeKind(kind: "locality", kindDetail: "town") == .town)
		#expect(OfflineVectorTileProvider.placeKind(kind: "locality", kindDetail: "hamlet") == .village)
		#expect(OfflineVectorTileProvider.placeKind(kind: "macrohood", kindDetail: "quarter") == .suburb)
		#expect(OfflineVectorTileProvider.placeKind(kind: "neighbourhood", kindDetail: "suburb") == .neighborhood)
		#expect(OfflineVectorTileProvider.placeKind(kind: "country", kindDetail: nil) == nil)
	}

	@Test("an older basemap's pmap:kind and place name the same kinds")
	func olderSchemaPlaceKinds() {
		#expect(OfflineVectorTileProvider.placeKind(["pmap:kind": "locality", "place": "city"]) == .city)
		#expect(OfflineVectorTileProvider.placeKind(["pmap:kind": "locality", "place": "town"]) == .town)
		#expect(OfflineVectorTileProvider.placeKind(["pmap:kind": "neighbourhood", "place": "neighbourhood"]) == .neighborhood)
		#expect(OfflineVectorTileProvider.placeKind(["pmap:kind": "country"]) == nil)
		#expect(OfflineVectorTileProvider.placeKind(["kind": "locality", "kind_detail": "town", "place": "city"]) == .town)
	}

	@Test("a population rank too big or not a number reads as a small integer, without trapping")
	func ranks() {
		#expect(OfflineVectorTileProvider.labelRank(UInt64.max) == 1_000)
		#expect(OfflineVectorTileProvider.labelRank(Double.infinity) == 0)
		#expect(OfflineVectorTileProvider.labelRank(Double.nan) == 0)
		#expect(OfflineVectorTileProvider.labelRank(Int64(7)) == 7)
		#expect(OfflineVectorTileProvider.labelRank("7") == 0)
	}

	@Test("the name is in the app's language when the map has it")
	func localizedNames() {
		let properties: [String: Sendable] = ["name": "München", "name:en": "Munich", "name:zh-Hant": "慕尼黑"]
		#expect(OfflineVectorTileProvider.localizedName(properties, language: Locale.Language(identifier: "en")) == "Munich")
		#expect(OfflineVectorTileProvider.localizedName(properties, language: Locale.Language(identifier: "zh-Hant")) == "慕尼黑")
		#expect(OfflineVectorTileProvider.localizedName(properties, language: Locale.Language(identifier: "de")) == "München")
		#expect(OfflineVectorTileProvider.localizedName(["name": ""], language: Locale.Language(identifier: "en")) == nil)
	}

	@Test("a label waits for its zoom")
	func minZoom() {
		let frame = SpatialFrame(bounds: box)
		let labels = [label("Seattle", .city, minZoom: 4), label("Belltown", .neighborhood, lat: 47.68, minZoom: 13)]
		let wide = SpatialOfflineLabels.place(labels, frame: frame, size: size, zoom: 11, dark: false)
		#expect(wide.map(\.label.name) == ["Seattle"])
		let close = SpatialOfflineLabels.place(labels, frame: frame, size: size, zoom: 14, dark: false)
		#expect(close.map(\.label.name) == ["Seattle", "Belltown"])
	}

	@Test("of two labels in the same spot, the bigger place wins")
	func collisions() {
		let frame = SpatialFrame(bounds: box)
		let labels = [label("Smallville", .town, rank: 3), label("Bigtown", .town, lon: -122.301, rank: 9), label("Seattle", .city, lat: 47.65)]
		let placed = SpatialOfflineLabels.place(labels, frame: frame, size: size, zoom: 11, dark: false)
		#expect(placed.map(\.label.name) == ["Seattle", "Bigtown"])
		for (a, b) in zip(placed, placed.dropFirst()) {
			#expect(!a.rect.intersects(b.rect))
		}
	}

	@Test("labels at the edge of the round map are left out")
	func diskEdge() {
		let frame = SpatialFrame(bounds: box)
		// The box's corner is outside the disk.
		let placed = SpatialOfflineLabels.place([label("Corner", .city, lat: 47.74, lon: -122.49)], frame: frame, size: size, zoom: 11, dark: false)
		#expect(placed.isEmpty)
	}

	@Test("drawing prints the labels over the image")
	func draw() throws {
		let frame = SpatialFrame(bounds: box)
		let width = 512
		let context = try #require(CGContext(data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: 0,
											 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
		context.fill(CGRect(x: 0, y: 0, width: width, height: width))
		let image = try #require(context.makeImage())
		let labeled = try #require(SpatialOfflineLabels.draw([label("Seattle", .city, minZoom: 0)], over: image, frame: frame, dark: false))
		let pixels = try #require(labeled.dataProvider?.data as Data?)
		// Dark text and its white outline both land around the middle.
		var darkest = 255, lightest = 0
		for y in (width / 2 - 12)...(width / 2 + 12) {
			for x in (width / 2 - 60)...(width / 2 + 60) {
				let value = Int(pixels[y * labeled.bytesPerRow + x * 4])
				darkest = min(darkest, value)
				lightest = max(lightest, value)
			}
		}
		#expect(darkest < 90)
		#expect(lightest > 200)
	}

	// MARK: Landmarks and streets

	private func street(_ name: String, from start: (Double, Double), to end: (Double, Double), minZoom: Double = 8) -> OfflineMapLabel {
		let a = CLLocationCoordinate2D(latitude: start.0, longitude: start.1)
		let b = CLLocationCoordinate2D(latitude: end.0, longitude: end.1)
		let middle = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
		return OfflineMapLabel(name: name, coordinate: middle, kind: .road, minZoom: minZoom, rank: 3, along: (a, b))
	}

	@Test("a tile gives landmark names from the pois layer and street names from the roads layer")
	func landmarksAndStreetsFromATile() throws {
		let bounds = GeoBounds.tile(z: 14, x: 2624, y: 5722)
		let middle = GISTools.Coordinate3D(latitude: (bounds.minLat + bounds.maxLat) / 2, longitude: (bounds.minLon + bounds.maxLon) / 2)
		let west = GISTools.Coordinate3D(latitude: middle.latitude, longitude: bounds.minLon + 0.1 * (bounds.maxLon - bounds.minLon))
		let east = GISTools.Coordinate3D(latitude: middle.latitude, longitude: bounds.maxLon - 0.1 * (bounds.maxLon - bounds.minLon))
		var vector = try #require(VectorTile(x: 2624, y: 5722, z: 14))
		vector.setFeatures([
			GISTools.Feature(GISTools.Point(middle), properties: ["kind": "park", "name": "Volunteer Park", "min_zoom": 13.0]),
			GISTools.Feature(GISTools.Point(middle), properties: ["kind": "retail", "name": "Corner Shop", "min_zoom": 15.0])
		], for: "pois")
		let decoded: GISTools.LineString? = GISTools.LineString([west, east])
		let line = try #require(decoded)
		vector.setFeatures([
			GISTools.Feature(line, properties: ["kind": "major_road", "kind_detail": "primary", "name": "Main Street", "min_zoom": 8.0]),
			GISTools.Feature(line, properties: ["kind": "path", "kind_detail": "footway", "name": "Trail"])
		], for: "roads")
		let labels = OfflineVectorTileProvider.labels(in: vector, bounds: bounds)
		#expect(labels.filter { $0.kind == .landmark }.map(\.name) == ["Volunteer Park"])
		let streets = labels.filter { $0.kind == .road }
		#expect(streets.map(\.name) == ["Main Street"])
		// A main road's name waits for zoom 12 even when the road itself shows from further out.
		#expect(streets.first?.minZoom == 12)
		#expect(streets.first?.along != nil)
	}

	@Test("a street name follows the longest straight stretch, and a short one gets none")
	func straightRuns() throws {
		// A long run east, a sharp turn north, then a short run.
		let points = [
			CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33),
			CLLocationCoordinate2D(latitude: 47.6, longitude: -122.32),
			CLLocationCoordinate2D(latitude: 47.6, longitude: -122.31),
			CLLocationCoordinate2D(latitude: 47.601, longitude: -122.31)
		]
		let run = try #require(OfflineVectorTileProvider.longestStraightRun(points, within: nil))
		#expect(run.start.longitude == -122.33)
		#expect(run.end.longitude == -122.31)
		let short = [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33), CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3299)]
		#expect(OfflineVectorTileProvider.longestStraightRun(short, within: nil) == nil)
	}

	@Test("a street name reads left to right whichever way the street was drawn")
	func readableAngles() {
		let east = SpatialOfflineLabels.readableAngle(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))
		let west = SpatialOfflineLabels.readableAngle(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 0, y: 0))
		#expect(abs(east - west) < 0.0001)
		#expect(abs(east - .pi / 4) < 0.0001)
	}

	@Test("the same street's name is printed once nearby, again further along, and not on a stretch shorter than the name")
	func streetSpacing() {
		let frame = SpatialFrame(bounds: box)
		let labels = [
			street("Aurora Avenue", from: (47.60, -122.42), to: (47.60, -122.36)),
			street("Aurora Avenue", from: (47.61, -122.42), to: (47.61, -122.36)),
			street("Aurora Avenue", from: (47.60, -122.24), to: (47.60, -122.18)),
			street("Tiny Lane", from: (47.55, -122.30), to: (47.55, -122.2999))
		]
		let placed = SpatialOfflineLabels.place(labels, frame: frame, size: size, zoom: 14, dark: false)
		#expect(placed.map(\.label.name) == ["Aurora Avenue", "Aurora Avenue"])
		#expect(placed.allSatisfy { abs($0.angle) < 0.01 })
	}

	@Test("a landmark gives way to a place in the same spot")
	func landmarksYieldToPlaces() {
		let frame = SpatialFrame(bounds: box)
		let labels = [label("Volunteer Park", .landmark), label("Capitol Hill", .neighborhood)]
		let placed = SpatialOfflineLabels.place(labels, frame: frame, size: size, zoom: 14, dark: false)
		#expect(placed.map(\.label.name) == ["Capitol Hill"])
	}
}
