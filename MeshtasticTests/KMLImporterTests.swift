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

		let manager = MapDataManager.shared
		let metadata = try await manager.processUploadedFile(from: url)
		var removed = false
		defer { if !removed { Task { try? await manager.deleteFile(metadata) } } }

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
		removed = true
		#expect(!FileManager.default.fileExists(atPath: assetsDirectory.path))
	}

	@Test("A KML imports as a layer of its shapes")
	func importKML() async throws {
		let url = try write(Data(document.utf8), named: "Plain \(UUID().uuidString).kml")
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
		let manager = MapDataManager.shared
		let metadata = try await manager.processUploadedFile(from: url)
		defer { Task { try? await manager.deleteFile(metadata) } }
		#expect(metadata.overlayCount == 2)
		#expect(manager.groundOverlays(for: [metadata]).isEmpty)
	}

	@Test("A KMZ renamed to .kml is still read as a KMZ")
	func renamedKMZ() async throws {
		let archive = TestZip.make([.init(name: "doc.kml", data: Data(document.utf8))])
		let url = try write(archive, named: "Renamed \(UUID().uuidString).kml")
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
		let manager = MapDataManager.shared
		let metadata = try await manager.processUploadedFile(from: url)
		defer { Task { try? await manager.deleteFile(metadata) } }
		#expect(metadata.overlayCount == 2)
	}

	@Test("A file that isn't KML, or is empty of anything drawable, is refused with a reason")
	func refusals() async throws {
		let html = try write(Data("<html/>".utf8), named: "page-\(UUID().uuidString).kml")
		let empty = try write(Data("<kml xmlns=\"http://www.opengis.net/kml/2.2\"/>".utf8), named: "empty-\(UUID().uuidString).kml")
		let notZip = try write(Data([0x50, 0x4B, 0x03, 0x04, 0, 0]), named: "bad-\(UUID().uuidString).kmz")
		defer { [html, empty, notZip].forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }
		let manager = MapDataManager.shared
		await #expect(throws: KMLConverterError.self) { try await manager.processUploadedFile(from: html) }
		await #expect(throws: MapDataError.self) { try await manager.processUploadedFile(from: empty) }
		await #expect(throws: KMZArchiveError.self) { try await manager.processUploadedFile(from: notZip) }
	}

	@Test("The size limit is the one Android uses for shared map files")
	func sizeLimit() {
		#expect(MapDataManager.maxFileSize == 50 * 1024 * 1024)
		#expect(MapDataError.fileTooLarge.errorDescription?.contains("50") == true)
	}
}
