//
//  KMLImporterTests.swift
//  MeshtasticTests
//

import Foundation
import MapKit
import Testing
import UIKit
@testable import Meshtastic

@Suite("KML import", .serialized)
struct KMLImporterTests {

	// MARK: - Fixtures

	private func png(width: Int = 8, height: Int = 4) -> Data {
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
			let format = UIGraphicsImageRendererFormat()
			format.scale = 1
			return format
		}())
		return renderer.pngData { context in
			UIColor.red.setFill()
			context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
		}
	}

	private let document = """
	<?xml version="1.0" encoding="UTF-8"?>
	<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
	<Style id="pin"><IconStyle><scale>2</scale><Icon><href>files/pin.png</href></Icon></IconStyle></Style>
	<Placemark><name>Camp</name><styleUrl>#pin</styleUrl><Point><coordinates>-122.3,47.6</coordinates></Point></Placemark>
	<Placemark><name>Trail</name><LineString><coordinates>-122.3,47.6 -122.2,47.7</coordinates></LineString></Placemark>
	<GroundOverlay><name>Survey</name><Icon><href>images/survey.png</href></Icon>
	<LatLonBox><north>47.7</north><south>47.6</south><east>-122.2</east><west>-122.3</west><rotation>15</rotation></LatLonBox></GroundOverlay>
	</Document></kml>
	"""

	private func root(_ package: KMLImportPackage) throws -> [String: Any] {
		try #require(JSONSerialization.jsonObject(with: Data(package.geoJSON.utf8)) as? [String: Any])
	}

	// MARK: - Packaging

	@Test("A KMZ's images are kept and named by the layer that uses them")
	func packagesImages() throws {
		let image = png()
		let package = try KMLImporter.package(kml: Data(document.utf8)) { href in
			["files/pin.png": image, "images/survey.png": image][href]
		}
		#expect(package.featureCount == 2)
		#expect(package.groundOverlayCount == 1)
		#expect(package.assets.count == 2)
		#expect(package.assets.keys.allSatisfy { $0.hasSuffix(".png") })

		let json = try root(package)
		let features = try #require(json["features"] as? [[String: Any]])
		let point = try #require(features.first?["properties"] as? [String: Any])
		let iconName = try #require(point["icon-image"] as? String)
		#expect(package.assets[iconName] != nil)
		#expect(point["icon-href"] == nil, "the file's own reference is not kept")
		#expect(point["icon-scale"] as? Double == 2)

		let overlays = try #require(json["groundOverlays"] as? [[String: Any]])
		let overlay = try #require(overlays.first)
		#expect(package.assets[try #require(overlay["image"] as? String)] != nil)
		#expect(overlay["rotation"] as? Double == 15)
		#expect(overlay["name"] as? String == "Survey")
	}

	@Test("The same image used twice is stored once")
	func sharesImages() throws {
		let image = png()
		let kml = """
		<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
		<Style id="pin"><IconStyle><Icon><href>pin.png</href></Icon></IconStyle></Style>
		<Placemark><styleUrl>#pin</styleUrl><Point><coordinates>1,1</coordinates></Point></Placemark>
		<Placemark><styleUrl>#pin</styleUrl><Point><coordinates>2,2</coordinates></Point></Placemark>
		</Document></kml>
		"""
		let package = try KMLImporter.package(kml: Data(kml.utf8)) { $0 == "pin.png" ? image : nil }
		#expect(package.assets.count == 1)
	}

	@Test("A bare KML keeps its shapes and drops images it cannot reach")
	func bareKML() throws {
		let package = try KMLImporter.package(kml: Data(document.utf8)) { _ in nil }
		#expect(package.featureCount == 2)
		#expect(package.groundOverlayCount == 0)
		#expect(package.assets.isEmpty)
		let json = try root(package)
		#expect(json["groundOverlays"] == nil)
		let features = try #require(json["features"] as? [[String: Any]])
		let point = try #require(features.first?["properties"] as? [String: Any])
		#expect(point["icon-image"] == nil)
		#expect(point["icon-scale"] == nil)
	}

	@Test("A file that is not an image is left out, as is one that will not decode")
	func rejectsNonImages() throws {
		let package = try KMLImporter.package(kml: Data(document.utf8)) { _ in Data("not an image".utf8) }
		#expect(package.assets.isEmpty)
		#expect(package.groundOverlayCount == 0)
		var truncated = png()
		truncated.removeLast(truncated.count - 12)
		let second = try KMLImporter.package(kml: Data(document.utf8)) { _ in truncated }
		#expect(second.assets.isEmpty)
	}

	@Test("A KML with nothing the map can show is refused")
	func nothingToShow() {
		let onlyOverlay = """
		<kml xmlns="http://www.opengis.net/kml/2.2"><GroundOverlay><Icon><href>x.png</href></Icon>
		<LatLonBox><north>1</north><south>0</south><east>1</east><west>0</west></LatLonBox></GroundOverlay></kml>
		"""
		#expect(throws: MapDataError.self) { try KMLImporter.package(kml: Data(onlyOverlay.utf8)) { _ in nil } }
		#expect(throws: MapDataError.self) {
			try KMLImporter.package(kml: Data("<kml xmlns=\"http://www.opengis.net/kml/2.2\"/>".utf8)) { _ in nil }
		}
	}

	@Test("Image formats are recognized by their bytes, and oversized pictures are refused")
	func imageChecks() {
		#expect(KMLImporter.imageExtension(of: png()) == "png")
		#expect(KMLImporter.imageExtension(of: Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])) == "jpg")
		#expect(KMLImporter.imageExtension(of: Data("GIF89a".utf8)) == "gif")
		#expect(KMLImporter.imageExtension(of: Data("RIFF\0\0\0\0WEBPVP8 ".utf8)) == "webp")
		#expect(KMLImporter.imageExtension(of: Data("<svg/>".utf8)) == nil)
		#expect(KMLImporter.isDecodable(png()))
		#expect(!KMLImporter.isDecodable(Data()))
	}

	// MARK: - Through the layer store

	/// A layer store of its own, in a folder removed when the test ends, so the tests never touch the
	/// app's own map files.
	private func isolatedManager() -> (manager: MapDataManager, cleanup: () -> Void) {
		let directory = "MapDataTests-\(UUID().uuidString)"
		let manager = MapDataManager(directoryName: directory)
		return (manager, {
			if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
				try? FileManager.default.removeItem(at: documents.appendingPathComponent(directory))
			}
		})
	}


	private func write(_ data: Data, named name: String) throws -> URL {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let url = directory.appendingPathComponent(name)
		try data.write(to: url)
		return url
	}

	@Test("A KMZ imports as a layer, with its overlay and icon images saved beside it, and deleting it removes them")
	func importAndDeleteKMZ() async throws {
		let image = png()
		let archive = TestZip.make([
			.init(name: "doc.kml", data: Data(document.utf8), deflate: true),
			.init(name: "files/pin.png", data: image),
			.init(name: "images/survey.png", data: image, deflate: true)
		])
		let url = try write(archive, named: "Survey \(UUID().uuidString).kmz")
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

		let (manager, cleanup) = isolatedManager()
		defer { cleanup() }
		let metadata = try await manager.processUploadedFile(from: url)

		#expect(metadata.format == "geojson")
		#expect(metadata.overlayCount == 3, "two features and one ground overlay")

		let overlays = manager.groundOverlays(for: [metadata])
		#expect(overlays.count == 1)
		let overlay = try #require(overlays.first)
		#expect(FileManager.default.fileExists(atPath: overlay.imageURL.path))
		#expect(overlay.rotation == 15)
		#expect(overlay.makeOverlay() != nil)

		let styled = manager.loadFeatureCollectionForFiles([metadata])?.features ?? []
		let iconPath = styled.compactMap(\.importedIconPath).first
		#expect(iconPath != nil)
		#expect(iconPath.map { FileManager.default.fileExists(atPath: $0) } == true)

		let assetsDirectory = overlay.imageURL.deletingLastPathComponent()
		try await manager.deleteFile(metadata)
		#expect(!FileManager.default.fileExists(atPath: assetsDirectory.path))
	}

	@Test("A KML imports as a layer of its shapes")
	func importKML() async throws {
		let url = try write(Data(document.utf8), named: "Plain \(UUID().uuidString).kml")
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
		let (manager, cleanup) = isolatedManager()
		defer { cleanup() }
		let metadata = try await manager.processUploadedFile(from: url)
		#expect(metadata.overlayCount == 2)
		#expect(manager.groundOverlays(for: [metadata]).isEmpty)
	}

	@Test("A KMZ renamed to .kml is still read as a KMZ")
	func renamedKMZ() async throws {
		let archive = TestZip.make([.init(name: "doc.kml", data: Data(document.utf8))])
		let url = try write(archive, named: "Renamed \(UUID().uuidString).kml")
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
		let (manager, cleanup) = isolatedManager()
		defer { cleanup() }
		let metadata = try await manager.processUploadedFile(from: url)
		#expect(metadata.overlayCount == 2)
	}

	@Test("A file that isn't KML, or is empty of anything drawable, is refused with a reason")
	func refusals() async throws {
		let html = try write(Data("<html/>".utf8), named: "page-\(UUID().uuidString).kml")
		let empty = try write(Data("<kml xmlns=\"http://www.opengis.net/kml/2.2\"/>".utf8), named: "empty-\(UUID().uuidString).kml")
		let notZip = try write(Data([0x50, 0x4B, 0x03, 0x04, 0, 0]), named: "bad-\(UUID().uuidString).kmz")
		defer { [html, empty, notZip].forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }
		let (manager, cleanup) = isolatedManager()
		defer { cleanup() }
		await #expect(throws: KMLConverterError.self) { try await manager.processUploadedFile(from: html) }
		await #expect(throws: MapDataError.self) { try await manager.processUploadedFile(from: empty) }
		await #expect(throws: KMZArchiveError.self) { try await manager.processUploadedFile(from: notZip) }
	}

	// MARK: - Drawing

	/// A picture with a green top half and a blue bottom half, written to disk.
	private func halvesImage() throws -> URL {
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: {
			let format = UIGraphicsImageRendererFormat()
			format.scale = 1
			return format
		}())
		let data = renderer.pngData { _ in
			UIColor(red: 0, green: 1, blue: 0, alpha: 1).setFill()
			UIRectFill(CGRect(x: 0, y: 0, width: 20, height: 10))
			UIColor(red: 0, green: 0, blue: 1, alpha: 1).setFill()
			UIRectFill(CGRect(x: 0, y: 10, width: 20, height: 10))
		}
		return try write(data, named: "halves-\(UUID().uuidString).png")
	}

	private struct Pixel {
		var red: CGFloat
		var green: CGFloat
		var blue: CGFloat
	}

	/// Draws the overlay the way the map does, into a bitmap with the top-left origin MapKit uses,
	/// and returns the color near the middle of its top edge.
	private func topColor(of overlay: GroundImageOverlay) -> Pixel? {
		let rect = overlay.imageMapRect
		let side = 200
		guard let context = CGContext(
			data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
			space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else { return nil }
		// Top-left origin, with map points scaled so the overlay fills the bitmap. A renderer works
		// in map points measured from the overlay's own corner, not from the map's.
		context.translateBy(x: 0, y: CGFloat(side))
		context.scaleBy(x: 1, y: -1)
		context.scaleBy(x: CGFloat(side) / CGFloat(rect.size.width), y: CGFloat(side) / CGFloat(rect.size.height))
		GroundImageOverlayRenderer(overlay: overlay).draw(overlay.boundingMapRect, zoomScale: 1, in: context)
		guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
		// Row 0 of the bitmap is the top.
		let offset = 20 * side * 4 + (side / 2) * 4
		return Pixel(red: CGFloat(bytes[offset]) / 255, green: CGFloat(bytes[offset + 1]) / 255, blue: CGFloat(bytes[offset + 2]) / 255)
	}

	@Test("A ground overlay draws upright, reading its image from disk only when drawn")
	func drawsUpright() throws {
		let url = try halvesImage()
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
		let overlay = ImportedGroundOverlay(
			id: "t", name: nil, imageURL: url, north: 0.001, south: -0.001, east: 0.001, west: -0.001, rotation: 0
		).makeOverlay()
		let drawn = try #require(overlay)
		let color = try #require(topColor(of: drawn))
		#expect(color.green > 0.8 && color.blue < 0.2, "the top of the picture is green")
	}

	@Test("A ground overlay turned half a circle shows its other edge on top")
	func drawsTurned() throws {
		let url = try halvesImage()
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
		let overlay = try #require(ImportedGroundOverlay(
			id: "t", name: nil, imageURL: url, north: 0.001, south: -0.001, east: 0.001, west: -0.001, rotation: 180
		).makeOverlay())
		let color = try #require(topColor(of: overlay))
		#expect(color.blue > 0.8 && color.green < 0.2, "the bottom of the picture is now on top")
	}

	@Test("An overlay whose image file is gone is left out")
	func missingImage() {
		let gone = ImportedGroundOverlay(
			id: "t", name: nil, imageURL: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).png"),
			north: 1, south: 0, east: 1, west: 0, rotation: 0
		)
		#expect(gone.makeOverlay() == nil)
	}

	@Test("The size limit is the one Android uses for shared map files")
	func sizeLimit() {
		#expect(MapDataManager.maxFileSize == 50 * 1024 * 1024)
		#expect(MapDataError.fileTooLarge.errorDescription?.contains("50") == true)
	}
}
