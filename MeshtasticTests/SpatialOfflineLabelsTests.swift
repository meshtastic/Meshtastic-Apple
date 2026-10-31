//
//  SpatialOfflineLabelsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//
import CoreGraphics
import CoreLocation
import Foundation
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
}
