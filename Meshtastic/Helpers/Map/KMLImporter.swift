//
//  KMLImporter.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/24/26.
//
//  Turns a KML document (and, from a KMZ, the images it names) into the one thing the map's
//  layer store takes: a GeoJSON file, plus image files kept beside it.
//

import Foundation
import ImageIO

/// A converted KML, ready to store.
struct KMLImportPackage: Sendable {
	/// A GeoJSON `FeatureCollection`. Point features that name an icon carry `icon-image`, and any
	/// ground overlays sit in a top-level `groundOverlays` list (GeoJSON allows extra members).
	/// Both name files in `assets`.
	let geoJSON: String
	/// Image files by the name the GeoJSON uses for them.
	let assets: [String: Data]
	let featureCount: Int
	let groundOverlayCount: Int
	/// The `groundOverlays` list on its own, for the small file kept beside the images so drawing
	/// them never means reading the whole layer again.
	let groundOverlaysJSON: Data?
}

enum KMLImporter {
	/// The most the largest side of an imported image may be. Past this it is more likely a
	/// mistake than a map, and decoding it could use gigabytes.
	static let maxImagePixels = 16_384

	/// Builds a package from `kml`. `imageData` supplies the bytes for an image reference; pass one
	/// that returns nil for a bare KML, which has no files beside it to read. Images that aren't
	/// there, or won't decode, are left out and the features that named them still draw.
	/// Nothing here fetches from the web.
	static func package(kml: Data, imageData: (String) -> Data?) throws -> KMLImportPackage {
		let conversion = try KMLConverter.convert(kml)
		var assets: [String: Data] = [:]
		var assetNames: [String: String] = [:]

		func assetName(for href: String) -> String? {
			if let known = assetNames[href] { return known }
			guard let bytes = imageData(href), let ext = imageExtension(of: bytes), isDecodable(bytes) else { return nil }
			let name = "asset-\(assets.count).\(ext)"
			assets[name] = bytes
			assetNames[href] = name
			return name
		}

		let features: [[String: Any]] = conversion.features.map { feature in
			var feature = feature
			guard var properties = feature["properties"] as? [String: Any] else { return feature }
			if let href = properties.removeValue(forKey: "icon-href") as? String, let name = assetName(for: href) {
				properties["icon-image"] = name
			} else {
				properties.removeValue(forKey: "icon-scale")
			}
			feature["properties"] = properties
			return feature
		}

		let overlays: [[String: Any]] = conversion.groundOverlays.compactMap { overlay in
			guard let name = assetName(for: overlay.href) else { return nil }
			var entry: [String: Any] = [
				"image": name,
				"north": overlay.north,
				"south": overlay.south,
				"east": overlay.east,
				"west": overlay.west,
				"rotation": overlay.rotation
			]
			if let title = overlay.name, !title.isEmpty { entry["name"] = title }
			return entry
		}

		guard !features.isEmpty || !overlays.isEmpty else { throw MapDataError.noMappableContent }

		var root: [String: Any] = ["type": "FeatureCollection", "features": features]
		if !overlays.isEmpty { root["groundOverlays"] = overlays }
		let data = try JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes])
		let overlaysJSON = overlays.isEmpty ? nil : try JSONSerialization.data(withJSONObject: overlays, options: [.withoutEscapingSlashes])
		return KMLImportPackage(
			geoJSON: String(data: data, encoding: .utf8) ?? "",
			assets: assets,
			featureCount: features.count,
			groundOverlayCount: overlays.count,
			groundOverlaysJSON: overlaysJSON
		)
	}

	// MARK: - Images

	/// The file extension for the image formats a map layer may carry, read from the bytes.
	static func imageExtension(of bytes: Data) -> String? {
		let head = Array(bytes.prefix(12))
		if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
		if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
		if head.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
		if head.count >= 12, head.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(head[8..<12]) == [0x57, 0x45, 0x42, 0x50] {
			return "webp"
		}
		return nil
	}

	/// True when ImageIO can read the image and it is a sane size.
	static func isDecodable(_ bytes: Data) -> Bool {
		guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
			  CGImageSourceGetCount(source) > 0,
			  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
			  let width = properties[kCGImagePropertyPixelWidth] as? Int,
			  let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
		return width > 0 && height > 0 && max(width, height) <= maxImagePixels
	}
}
