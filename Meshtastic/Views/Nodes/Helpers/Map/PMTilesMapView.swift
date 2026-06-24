//
//  PMTilesMapView.swift
//  Meshtastic
//
//  A SwiftUI shim around `MKMapView` that displays an OFFLINE raster PMTiles archive
//  as the basemap (via `MKTileOverlay`) with a GeoJSON overlay drawn on top.
//
//  SwiftUI's `Map` can't host a custom `MKTileOverlay`, so this wraps `MKMapView` in a
//  `UIViewRepresentable`. MapKit only rasterizes tiles, so the PMTiles archive must be
//  RASTER (PNG/JPEG/WEBP) — vector (MVT) PMTiles need a vector renderer (MapLibre).
//

import MapKit
import OSLog
import SwiftUI

// MARK: - Tile overlay backed by a PMTiles archive

final class OfflineTileOverlay: MKTileOverlay {
	private let source: OfflineTileSource

	init(source: OfflineTileSource) {
		self.source = source
		super.init(urlTemplate: nil)
		self.tileSize = CGSize(width: 256, height: 256)
		self.minimumZ = Int(source.tileMinZoom)
		self.maximumZ = Int(source.tileMaxZoom)
		// Replace Apple's basemap entirely so the map is fully offline.
		self.canReplaceMapContent = true
	}

	override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
		// Both PMTiles and (after the source's own TMS flip) MBTiles are addressed by the
		// standard slippy-map (XYZ, origin top-left) scheme — same as MKTileOverlayPath.
		guard path.z >= 0, path.x >= 0, path.y >= 0,
			  let data = source.tileData(z: UInt8(path.z), x: UInt32(path.x), y: UInt32(path.y)) else {
			result(nil, nil) // no tile here — MapKit leaves it blank
			return
		}
		if source.isVectorTiles {
			// Rasterize the MVT to a PNG in Swift so MapKit can display it (no MapLibre).
			result(VectorTileRasterizer.png(mvt: data, z: path.z, x: path.x, y: path.y), nil)
		} else {
			result(data, nil) // already raster
		}
	}
}

// MARK: - GeoJSON styling (simplestyle-spec subset)

private struct GeoJSONStyle {
	var stroke = UIColor.systemRed
	var strokeWidth: CGFloat = 2
	var strokeOpacity: CGFloat = 1
	var fill = UIColor.systemTeal
	var fillOpacity: CGFloat = 0.2
	var marker = UIColor.systemRed
	var title: String?

	init(properties: [String: Any]?) {
		guard let properties else { return }
		if let value = properties["stroke"] as? String, let color = UIColor(hex: value) { stroke = color }
		if let value = properties["fill"] as? String, let color = UIColor(hex: value) { fill = color }
		if let value = properties["marker-color"] as? String, let color = UIColor(hex: value) { marker = color }
		if let value = properties["stroke-width"] as? NSNumber { strokeWidth = CGFloat(truncating: value) }
		if let value = properties["stroke-opacity"] as? NSNumber { strokeOpacity = CGFloat(truncating: value) }
		if let value = properties["fill-opacity"] as? NSNumber { fillOpacity = CGFloat(truncating: value) }
		title = (properties["name"] ?? properties["title"]) as? String
	}
}

/// Annotation that carries its marker color through to the view.
private final class StyledPointAnnotation: MKPointAnnotation {
	var markerColor: UIColor = .systemRed
}

// MARK: - SwiftUI representable

struct PMTilesMapView: UIViewRepresentable {
	/// Local offline raster tile archive (`.pmtiles` or `.mbtiles`) used as the basemap.
	let tilesURL: URL
	/// Optional GeoJSON overlay (e.g. the Bellevue bounding box) drawn on top.
	var geoJSONURL: URL?

	func makeCoordinator() -> Coordinator { Coordinator() }

	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.delegate = context.coordinator

		guard let source = OfflineTileSourceFactory.source(for: tilesURL) else {
			Logger.services.error("📦 [Offline] Failed to open \(tilesURL.lastPathComponent, privacy: .public); showing Apple basemap.")
			return mapView
		}

		let overlay = OfflineTileOverlay(source: source)
		mapView.addOverlay(overlay, level: .aboveLabels)

		// Draw the GeoJSON overlay (polygons/lines as overlays, points as annotations).
		if let geoJSONURL { context.coordinator.addGeoJSON(from: geoJSONURL, to: mapView) }

		// Frame the downloaded archive with the bounding box (same style as our test box).
		if let bounds = source.geographicBounds {
			context.coordinator.addBoundingBox(bounds, to: mapView)
		}

		// Frame the GeoJSON if present, else the archive's own bounds.
		if let region = context.coordinator.geoJSONRegion {
			mapView.setRegion(region, animated: false)
		} else if let bounds = source.geographicBounds {
			let center = CLLocationCoordinate2D(latitude: (bounds.minLat + bounds.maxLat) / 2,
												longitude: (bounds.minLon + bounds.maxLon) / 2)
			let span = MKCoordinateSpan(latitudeDelta: max(0.02, bounds.maxLat - bounds.minLat),
										longitudeDelta: max(0.02, bounds.maxLon - bounds.minLon))
			mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
		}
		return mapView
	}

	func updateUIView(_ uiView: MKMapView, context: Context) {}

	// MARK: Coordinator

	final class Coordinator: NSObject, MKMapViewDelegate {
		private var styles: [ObjectIdentifier: GeoJSONStyle] = [:]
		private(set) var geoJSONRegion: MKCoordinateRegion?

		/// Adds a styled rectangle around the archive's geographic bounds — the "box around the
		/// downloaded protomap" — using the same look as the test GeoJSON box.
		func addBoundingBox(_ bounds: GeoBounds, to mapView: MKMapView) {
			let corners = [
				CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon),
				CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.maxLon),
				CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon),
				CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.minLon)
			]
			let polygon = MKPolygon(coordinates: corners, count: corners.count)
			var style = GeoJSONStyle(properties: nil)
			style.stroke = UIColor(hex: "#E76F51") ?? .systemOrange
			style.strokeWidth = 3
			style.fill = UIColor(hex: "#2A9D8F") ?? .systemTeal
			style.fillOpacity = 0.15
			styles[ObjectIdentifier(polygon)] = style
			mapView.addOverlay(polygon, level: .aboveLabels)

			if geoJSONRegion == nil {
				let rect = polygon.boundingMapRect
				geoJSONRegion = MKCoordinateRegion(rect.insetBy(dx: -rect.size.width * 0.12, dy: -rect.size.height * 0.12))
			}
		}

		/// Decodes a GeoJSON file with `MKGeoJSONDecoder` and adds its geometry to the map.
		func addGeoJSON(from url: URL, to mapView: MKMapView) {
			guard let data = try? Data(contentsOf: url),
				  let objects = try? MKGeoJSONDecoder().decode(data) else {
				Logger.services.error("📦 [PMTiles] Could not decode GeoJSON \(url.lastPathComponent, privacy: .public)")
				return
			}

			var rect = MKMapRect.null
			for case let feature as MKGeoJSONFeature in objects {
				let properties = feature.properties.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? nil
				let style = GeoJSONStyle(properties: properties)

				for geometry in feature.geometry {
					switch geometry {
					case let polygon as MKPolygon:
						styles[ObjectIdentifier(polygon)] = style
						mapView.addOverlay(polygon, level: .aboveLabels)
						rect = rect.union(polygon.boundingMapRect)
					case let polyline as MKPolyline:
						styles[ObjectIdentifier(polyline)] = style
						mapView.addOverlay(polyline, level: .aboveLabels)
						rect = rect.union(polyline.boundingMapRect)
					case let point as MKPointAnnotation:
						let annotation = StyledPointAnnotation()
						annotation.coordinate = point.coordinate
						annotation.title = style.title ?? point.title
						annotation.markerColor = style.marker
						mapView.addAnnotation(annotation)
						rect = rect.union(MKMapRect(origin: MKMapPoint(point.coordinate), size: MKMapSize(width: 0, height: 0)))
					default:
						break // Multi* and other geometry types omitted for this shim
					}
				}
			}

			if !rect.isNull {
				let region = MKCoordinateRegion(rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.15))
				geoJSONRegion = region
			}
		}

		func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
			if let tileOverlay = overlay as? MKTileOverlay {
				return MKTileOverlayRenderer(tileOverlay: tileOverlay)
			}
			if let polygon = overlay as? MKPolygon {
				let style = styles[ObjectIdentifier(polygon)] ?? GeoJSONStyle(properties: nil)
				let renderer = MKPolygonRenderer(polygon: polygon)
				renderer.strokeColor = style.stroke.withAlphaComponent(style.strokeOpacity)
				renderer.fillColor = style.fill.withAlphaComponent(style.fillOpacity)
				renderer.lineWidth = style.strokeWidth
				return renderer
			}
			if let polyline = overlay as? MKPolyline {
				let style = styles[ObjectIdentifier(polyline)] ?? GeoJSONStyle(properties: nil)
				let renderer = MKPolylineRenderer(polyline: polyline)
				renderer.strokeColor = style.stroke.withAlphaComponent(style.strokeOpacity)
				renderer.lineWidth = style.strokeWidth
				return renderer
			}
			return MKOverlayRenderer(overlay: overlay)
		}

		func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
			guard let styled = annotation as? StyledPointAnnotation else { return nil }
			let identifier = "pmtiles.marker"
			let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
				?? MKMarkerAnnotationView(annotation: styled, reuseIdentifier: identifier)
			view.annotation = styled
			view.markerTintColor = styled.markerColor
			view.canShowCallout = true
			return view
		}
	}
}

// MARK: - Convenience UIColor(hex:)

private extension UIColor {
	/// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA` hex strings.
	convenience init?(hex: String) {
		var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
		if string.hasPrefix("#") { string.removeFirst() }
		if string.count == 3 { string = string.map { "\($0)\($0)" }.joined() }
		guard let value = UInt64(string, radix: 16) else { return nil }
		let r, g, b, a: CGFloat
		switch string.count {
		case 6:
			r = CGFloat((value & 0xFF0000) >> 16) / 255
			g = CGFloat((value & 0x00FF00) >> 8) / 255
			b = CGFloat(value & 0x0000FF) / 255
			a = 1
		case 8:
			r = CGFloat((value & 0xFF00_0000) >> 24) / 255
			g = CGFloat((value & 0x00FF_0000) >> 16) / 255
			b = CGFloat((value & 0x0000_FF00) >> 8) / 255
			a = CGFloat(value & 0x0000_00FF) / 255
		default:
			return nil
		}
		self.init(red: r, green: g, blue: b, alpha: a)
	}
}

// MARK: - Demo / test host

/// A simple host that loads a `.pmtiles` and a `.geojson` from the app's Documents directory.
/// Drop `bellevue.pmtiles` and `test-bellevue-bbox.geojson` into Documents (Files app →
/// On My iPhone → Meshtastic) and present this view to test offline rendering.
struct PMTilesMapDemoView: View {
	private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

	var body: some View {
		let geojson = documents.appendingPathComponent("test-bellevue-bbox.geojson")
		// Accept either container — whichever the rasterized output landed in.
		let tiles = ["bellevue.mbtiles", "bellevue.pmtiles"]
			.map { documents.appendingPathComponent($0) }
			.first { FileManager.default.fileExists(atPath: $0.path) }
		Group {
			if let tiles {
				PMTilesMapView(tilesURL: tiles,
							   geoJSONURL: FileManager.default.fileExists(atPath: geojson.path) ? geojson : nil)
					.ignoresSafeArea()
			} else {
				ContentUnavailableView(
					"No offline tiles",
					systemImage: "map",
					description: Text("Copy a raster bellevue.mbtiles or bellevue.pmtiles into the app's Documents folder to test offline tiles.")
				)
			}
		}
		.navigationTitle("Offline Tiles")
	}
}
