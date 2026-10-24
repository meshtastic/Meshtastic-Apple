//
//  GroundImageOverlay.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/24/26.
//
//  An image laid on the map between four edges, turned about its center: what a KML
//  `<GroundOverlay>` asks for, and what an imported layer keeps images for.
//

import CoreLocation
import ImageIO
import MapKit
import UIKit
import UniformTypeIdentifiers

// MARK: - File types

enum KMLFileTypes {
	static func isKMLOrKMZ(_ url: URL) -> Bool {
		["kml", "kmz"].contains(url.pathExtension.lowercased())
	}

	/// What the file picker offers beyond GeoJSON.
	static var contentTypes: [UTType] {
		[UTType(filenameExtension: "kml") ?? .xml, UTType(filenameExtension: "kmz") ?? .zip]
	}
}

// MARK: - Images

/// Decoded layer images, shrunk to what a map can use: a picture of several thousand pixels on a
/// side would be gigabytes decoded, and the map never shows it larger than the screen. Nothing else
/// holds on to a decoded image, so the cache can let go of the ones not in use.
final class ImportedImageCache: @unchecked Sendable {
	static let shared = ImportedImageCache()

	/// The most decoded pixel data kept at once. A 4,096-pixel overlay is 64 MB.
	private static let maxCacheBytes = 192 * 1024 * 1024

	private init() {
		cache.totalCostLimit = Self.maxCacheBytes
	}

	/// Longest side, in pixels, for a ground overlay, and for a point's icon.
	static let overlayPixels = 4_096
	static let iconPixels = 128

	private let cache = NSCache<NSString, CGImage>()

	func image(atPath path: String, maxPixels: Int) -> CGImage? {
		let key = "\(maxPixels)|\(path)" as NSString
		if let cached = cache.object(forKey: key) { return cached }
		guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceShouldCacheImmediately: true,
			kCGImageSourceThumbnailMaxPixelSize: maxPixels
		]
		guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
		cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
		return image
	}

	func icon(atPath path: String) -> UIImage? {
		image(atPath: path, maxPixels: Self.iconPixels).map { UIImage(cgImage: $0) }
	}
}

extension GeoJSONFeature {
	/// The saved image file a point draws as its icon, when its layer kept one.
	var importedIconPath: String? {
		if case .string(let path) = properties?["icon-path"] { return path }
		return nil
	}

	/// How much larger or smaller than the standard size the file asked for the icon.
	var importedIconScale: Double {
		switch properties?["icon-scale"] {
		case .double(let scale): return scale
		case .int(let scale): return Double(scale)
		default: return 1
		}
	}
}

// MARK: - Overlay

/// An imported ground overlay as saved: the image file and where it goes.
struct ImportedGroundOverlay: Identifiable {
	let id: String
	let name: String?
	let imageURL: URL
	let north: Double
	let south: Double
	let east: Double
	let west: Double
	/// Degrees counterclockwise, as KML states it.
	let rotation: Double

	/// The map overlay, or nil when the image file is missing or the edges can't be drawn (an overlay
	/// that crosses the antimeridian, or one with its edges the wrong way round). The image itself is
	/// read when the map draws it, not here, so a layer with many images costs memory only for the
	/// ones on screen.
	func makeOverlay() -> GroundImageOverlay? {
		guard north > south, east > west, FileManager.default.fileExists(atPath: imageURL.path) else { return nil }
		return GroundImageOverlay(imagePath: imageURL.path, north: north, south: south, east: east, west: west, rotation: rotation)
	}
}

final class GroundImageOverlay: NSObject, MKOverlay {
	let imagePath: String
	let rotation: Double
	/// Where the image goes before it is turned.
	let imageMapRect: MKMapRect
	let coordinate: CLLocationCoordinate2D
	let boundingMapRect: MKMapRect

	init(imagePath: String, north: Double, south: Double, east: Double, west: Double, rotation: Double) {
		self.imagePath = imagePath
		self.rotation = rotation
		let northWest = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
		let southEast = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
		let rect = MKMapRect(
			x: northWest.x, y: northWest.y,
			width: southEast.x - northWest.x, height: southEast.y - northWest.y
		)
		self.imageMapRect = rect
		self.coordinate = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
		self.boundingMapRect = Self.bounds(of: rect, turnedByDegrees: rotation)
	}

	/// The smallest rect holding `rect` after it is turned about its center, so MapKit asks for
	/// every part the image reaches. Map points run down, so a counterclockwise turn is a negative
	/// angle here.
	private static func bounds(of rect: MKMapRect, turnedByDegrees degrees: Double) -> MKMapRect {
		guard degrees != 0 else { return rect }
		let angle = -degrees * .pi / 180
		let center = MKMapPoint(x: rect.midX, y: rect.midY)
		let corners = [
			MKMapPoint(x: rect.minX, y: rect.minY), MKMapPoint(x: rect.maxX, y: rect.minY),
			MKMapPoint(x: rect.maxX, y: rect.maxY), MKMapPoint(x: rect.minX, y: rect.maxY)
		].map { corner -> MKMapPoint in
			let dx = corner.x - center.x
			let dy = corner.y - center.y
			return MKMapPoint(
				x: center.x + dx * cos(angle) - dy * sin(angle),
				y: center.y + dx * sin(angle) + dy * cos(angle)
			)
		}
		let xs = corners.map(\.x)
		let ys = corners.map(\.y)
		guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return rect }
		return MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
	}
}

final class GroundImageOverlayRenderer: MKOverlayRenderer {
	override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
		// MapKit draws on a background thread, which is where a cache miss decodes the image.
		guard let overlay = overlay as? GroundImageOverlay,
			  let image = ImportedImageCache.shared.image(atPath: overlay.imagePath, maxPixels: ImportedImageCache.overlayPixels)
		else { return }
		let rect = self.rect(for: overlay.imageMapRect)
		context.saveGState()
		defer { context.restoreGState() }
		// Turn about the image's center. The renderer's space runs down, like UIKit's, so a
		// counterclockwise turn on screen is a negative angle.
		context.translateBy(x: rect.midX, y: rect.midY)
		context.rotate(by: CGFloat(-overlay.rotation * .pi / 180))
		context.translateBy(x: -rect.midX, y: -rect.midY)
		UIGraphicsPushContext(context)
		UIImage(cgImage: image).draw(in: rect)
		UIGraphicsPopContext()
	}
}
