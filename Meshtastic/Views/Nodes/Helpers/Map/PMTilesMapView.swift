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

import GISTools
import MapKit
import MVTTools
import OSLog
import SwiftUI

// MARK: - Tile overlay backed by a PMTiles archive

final class OfflineTileOverlay: MKTileOverlay {
	private let source: OfflineTileSource
	/// Selects the dark color palette when rasterizing vector tiles.
	let dark: Bool

	init(source: OfflineTileSource, dark: Bool = false) {
		self.source = source
		self.dark = dark
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
			result(VectorTileRasterizer.png(mvt: data, z: path.z, x: path.x, y: path.y, dark: dark), nil)
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

	@Environment(\.colorScheme) private var colorScheme

	func makeCoordinator() -> Coordinator { Coordinator() }

	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.delegate = context.coordinator

		guard let source = OfflineTileSourceFactory.source(for: tilesURL) else {
			Logger.services.error("📦 [Offline] Failed to open \(tilesURL.lastPathComponent, privacy: .public); showing Apple basemap.")
			return mapView
		}
		context.coordinator.source = source

		let overlay = OfflineTileOverlay(source: source, dark: colorScheme == .dark)
		context.coordinator.tileOverlay = overlay
		mapView.addOverlay(overlay, level: .aboveLabels)

		// Draw the GeoJSON overlay (lines as overlays, points as annotations).
		if let geoJSONURL { context.coordinator.addGeoJSON(from: geoJSONURL, to: mapView) }

		// Remember the archive extent + zoom range; the border is drawn dynamically per zoom
		// (see updateBoundingBox) so it always sits on the actual rendered tile edges.
		context.coordinator.requestedBounds = source.geographicBounds
		context.coordinator.minZoom = Int(source.tileMinZoom)
		context.coordinator.maxZoom = Int(source.tileMaxZoom)

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

		// Draw the initial tile-aligned border for the now-set region.
		context.coordinator.updateBoundingBox(on: mapView)
		return mapView
	}

	func updateUIView(_ uiView: MKMapView, context: Context) {
		// On a light/dark switch, swap the tile overlay so MapKit re-requests tiles, which the
		// rasterizer then renders with the matching palette (same .pmtiles data).
		guard let source = context.coordinator.source else { return }
		let wantsDark = colorScheme == .dark
		if context.coordinator.tileOverlay?.dark != wantsDark {
			if let old = context.coordinator.tileOverlay { uiView.removeOverlay(old) }
			let overlay = OfflineTileOverlay(source: source, dark: wantsDark)
			context.coordinator.tileOverlay = overlay
			uiView.addOverlay(overlay, level: .aboveLabels)
		}
	}

	// MARK: Coordinator

	final class Coordinator: NSObject, MKMapViewDelegate {
		private var styles: [ObjectIdentifier: GeoJSONStyle] = [:]
		private(set) var geoJSONRegion: MKCoordinateRegion?
		/// Retained so the overlay can be rebuilt with the dark/light palette on appearance change.
		var source: OfflineTileSource?
		var tileOverlay: OfflineTileOverlay?
		/// Archive extent + zoom range, used to redraw the tile-aligned border per zoom.
		var requestedBounds: GeoBounds?
		var minZoom = 0
		var maxZoom = 22
		private var boxOverlay: MKPolygon?
		private var lastBoxZoom: Int?

		func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
			updateBoundingBox(on: mapView)
		}

		/// Draws (or redraws) the border snapped to the tile grid at the map's CURRENT zoom, so it
		/// lands on the actual rendered tile edges rather than floating off them.
		func updateBoundingBox(on mapView: MKMapView) {
			guard let bounds = requestedBounds else { return }
			let zoom = currentTileZoom(mapView)
			guard zoom != lastBoxZoom else { return }
			lastBoxZoom = zoom

			if let old = boxOverlay {
				styles[ObjectIdentifier(old)] = nil
				mapView.removeOverlay(old)
			}

			let aligned = tileAlignedBounds(bounds, zoom: zoom)
			let corners = [
				CLLocationCoordinate2D(latitude: aligned.minLat, longitude: aligned.minLon),
				CLLocationCoordinate2D(latitude: aligned.minLat, longitude: aligned.maxLon),
				CLLocationCoordinate2D(latitude: aligned.maxLat, longitude: aligned.maxLon),
				CLLocationCoordinate2D(latitude: aligned.maxLat, longitude: aligned.minLon)
			]
			let polygon = MKPolygon(coordinates: corners, count: corners.count)
			var style = GeoJSONStyle(properties: nil)
			style.stroke = UIColor(hex: "#E76F51") ?? .systemOrange
			style.strokeWidth = 2
			style.fill = .clear
			style.fillOpacity = 0
			styles[ObjectIdentifier(polygon)] = style
			boxOverlay = polygon
			mapView.addOverlay(polygon, level: .aboveLabels)
		}

		/// Integer slippy-map zoom for the map's current span, clamped to the archive's range.
		/// Above maxZoom MapKit upsamples maxZoom tiles, so the data footprint stays maxZoom-aligned.
		private func currentTileZoom(_ mapView: MKMapView) -> Int {
			let width = max(1.0, Double(mapView.bounds.width))
			let lonDelta = max(1e-9, mapView.region.span.longitudeDelta)
			let zoom = log2(360.0 * width / (lonDelta * 256.0))
			return min(maxZoom, max(minZoom, Int(zoom.rounded())))
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

// MARK: - Tile-aligned bounds

/// Expands `bounds` outward to the slippy-map tile grid at `zoom` (Web Mercator), so the
/// returned box exactly encloses the tiles that a `--bbox` extract would include.
private func tileAlignedBounds(_ bounds: GeoBounds, zoom: Int) -> GeoBounds {
	let n = Double(1 << max(0, zoom))
	func lonToX(_ lon: Double) -> Int { Int(floor((lon + 180.0) / 360.0 * n)) }
	func latToY(_ lat: Double) -> Int {
		let r = lat * .pi / 180.0
		return Int(floor((1.0 - log(tan(r) + 1.0 / cos(r)) / .pi) / 2.0 * n))
	}
	func xToLon(_ x: Int) -> Double { Double(x) / n * 360.0 - 180.0 }
	func yToLat(_ y: Int) -> Double { atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n))) * 180.0 / .pi }

	let x0 = min(lonToX(bounds.minLon), lonToX(bounds.maxLon))
	let x1 = max(lonToX(bounds.minLon), lonToX(bounds.maxLon))
	let y0 = min(latToY(bounds.minLat), latToY(bounds.maxLat)) // north
	let y1 = max(latToY(bounds.minLat), latToY(bounds.maxLat)) // south
	return GeoBounds(minLon: xToLon(x0), minLat: yToLat(y1 + 1),
					 maxLon: xToLon(x1 + 1), maxLat: yToLat(y0))
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

// MARK: - Transparent offline-tile overlay (composited over a SwiftUI Map)

/// A non-interactive `MKMapView` that shows Apple's basemap (the "regular surrounding tiles") with
/// the offline archive's tiles drawn ON TOP only where they exist, kept in sync with the SwiftUI
/// `Map`'s camera via `region`. The offline tile overlay uses `canReplaceMapContent = false`, so
/// Apple's map keeps drawing everywhere the archive has no tiles. Because compositing two map
/// engines can't show Apple's basemap *through* a transparent top map, this top map is the one that
/// provides the surrounding Apple tiles — it covers the SwiftUI mesh map (and its nodes) beneath it.
/// Caveat: two map engines can't be perfectly frame-synced, so the tiles lag/swim during gestures.
struct OfflineTileMapOverlay: UIViewRepresentable {
	let tilesURL: URL
	var region: MKCoordinateRegion
	var dark: Bool

	func makeCoordinator() -> Coordinator { Coordinator() }

	private func makeOverlay(source: OfflineTileSource) -> OfflineTileOverlay {
		let overlay = OfflineTileOverlay(source: source, dark: dark)
		overlay.canReplaceMapContent = false // keep Apple's basemap as the surrounding tiles
		return overlay
	}

	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.isUserInteractionEnabled = false
		mapView.showsUserLocation = false
		mapView.pointOfInterestFilter = .excludingAll
		mapView.delegate = context.coordinator

		if let source = OfflineTileSourceFactory.source(for: tilesURL) {
			context.coordinator.source = source
			let overlay = makeOverlay(source: source)
			context.coordinator.tileOverlay = overlay
			mapView.addOverlay(overlay, level: .aboveLabels)
		}
		mapView.setRegion(region, animated: false)
		return mapView
	}

	func updateUIView(_ mapView: MKMapView, context: Context) {
		mapView.setRegion(region, animated: false) // track the SwiftUI map's camera
		if context.coordinator.tileOverlay?.dark != dark, let source = context.coordinator.source {
			if let old = context.coordinator.tileOverlay { mapView.removeOverlay(old) }
			let overlay = makeOverlay(source: source)
			context.coordinator.tileOverlay = overlay
			mapView.addOverlay(overlay, level: .aboveLabels)
		}
	}

	final class Coordinator: NSObject, MKMapViewDelegate {
		var source: OfflineTileSource?
		var tileOverlay: OfflineTileOverlay?
		func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
			if let tile = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tile) }
			return MKOverlayRenderer(overlay: overlay)
		}
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

// MARK: - Native vector rendering of offline MVT tiles (drawn IN a SwiftUI Map)
//
// Instead of rasterizing the Protomaps vector tiles to PNG (MKTileOverlay), decode them with
// mvt-tools straight into native MapKit shapes (MapPolygon/MapPolyline). SwiftUI's `Map` can't host
// raster tiles, but it renders vector `MapContent` natively — so the offline basemap composites
// directly with the map's own annotations (nodes), with Apple Maps as the surrounding basemap.
// No second map, no rasterization, no occlusion, no camera-swim.

/// Semantic role for an offline vector feature, mapped to a color/width at render time so a single
/// decode serves both light and dark appearance.
enum OfflineFeatureRole {
	case water, park, green, land
	case majorRoad, mediumRoad, minorRoad, path, rail, boundary
}

struct OfflineMapPolygon: Identifiable {
	let id: String
	let role: OfflineFeatureRole
	let coordinates: [CLLocationCoordinate2D]
}

struct OfflineMapPolyline: Identifiable {
	let id: String
	let role: OfflineFeatureRole
	let coordinates: [CLLocationCoordinate2D]
}

/// Render-ready offline content plus measurement stats (returned by `OfflineVectorTileProvider.build`).
struct BuildResult {
	let polygons: [OfflineMapPolygon]
	let polylines: [OfflineMapPolyline]
	let stats: OfflineDecodeStats
}

/// Quantitative measurement of one decode+stitch pass — drives the perf benchmark.
struct OfflineDecodeStats: CustomStringConvertible {
	let tiles: Int
	let zoom: Int
	let polygons: Int
	let rawSegments: Int
	let stitchedRoads: Int
	let rawVertices: Int
	let stitchedVertices: Int
	let decode: Duration
	let stitch: Duration

	/// Overlay count is the dominant SwiftUI-Map cost; this is what we're driving down.
	var overlayCount: Int { polygons + stitchedRoads }

	var description: String {
		let segReduction = rawSegments > 0 ? Int(100.0 * (1 - Double(stitchedRoads) / Double(rawSegments))) : 0
		return "z\(zoom) \(tiles) tiles | \(polygons) fills + \(rawSegments) segs → \(stitchedRoads) roads (-\(segReduction)%) | overlays=\(overlayCount) | verts \(rawVertices)→\(stitchedVertices) | decode \(decode.formatted()) stitch \(stitch.formatted())"
	}
}

/// Decodes the vector tiles inside a `.pmtiles` archive into native MapKit shapes for the visible
/// region. Decoding runs on a serial background queue (the archive is touched from one queue only);
/// results are published on the main actor for SwiftUI `Map` to render.
@MainActor
final class OfflineVectorTileProvider: ObservableObject {
	/// Water/park fills and roads, each as individual overlays. SwiftUI `Map` has no multi-shape
	/// overlay, so overlay COUNT is the dominant cost — roads are stitched (see `stitch`) from
	/// thousands of short MVT segments into a few hundred long polylines with the identical look.
	@Published private(set) var polygons: [OfflineMapPolygon] = []
	/// Arterials (major/medium/rail) — shown whenever the box is on screen.
	@Published private(set) var arterials: [OfflineMapPolyline] = []
	/// Residential street grid (minor) — shown only when zoomed into a neighborhood (level-of-detail).
	@Published private(set) var streets: [OfflineMapPolyline] = []

	let isAvailable: Bool
	/// The archive's coverage box (for the base fill + coverage rectangle), nil if unavailable.
	let coverageBounds: GeoBounds?
	private let source: OfflineTileSource?
	private let queue = DispatchQueue(label: "offline.vector.decode", qos: .userInitiated)
	private var didLoad = false

	/// `boundsTiles` picks the highest fixed zoom whose tile count fits this cap. Residential
	/// streets only exist in Protomaps tiles at z13+, so ~48 lands on z14 (full street grid).
	private let maxTiles = 48

	struct TileID {
		let z, x, y: Int
		var key: String { "\(z)/\(x)/\(y)" }
	}

	init(url: URL? = OfflineVectorTileProvider.defaultURL) {
		if let url, let source = OfflineTileSourceFactory.source(for: url), source.isVectorTiles {
			self.source = source
			self.isAvailable = true
			self.coverageBounds = source.geographicBounds
		} else {
			self.source = nil
			self.isAvailable = false
			self.coverageBounds = nil
		}
	}

	nonisolated static var defaultURL: URL? {
		let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("bellevue.pmtiles")
		return FileManager.default.fileExists(atPath: url.path) ? url : nil
	}

	/// Decode the whole coverage box ONCE at a fixed detail zoom, stitch road segments per role, and
	/// publish a single time. Vector geometry is resolution-independent, so it renders at every map
	/// zoom with no reload (no flashing). Decoded once and never replaced — no per-pan overlay churn.
	func updateIfNeeded() {
		guard !didLoad, let source, let bounds = source.geographicBounds else { return }
		didLoad = true
		let tiles = Self.boundsTiles(source: source, bounds: bounds, maxTiles: maxTiles)
		guard !tiles.isEmpty else { didLoad = false; return }
		queue.async { [weak self] in
			let result = Self.build(source: source, bounds: bounds, tiles: tiles)
			Logger.services.info("📦 [Offline] \(result.stats.description)")
			let arterials = result.polylines.filter { Self.isArterial($0.role) }
			let streets = result.polylines.filter { !Self.isArterial($0.role) }
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.polygons = result.polygons
				self.arterials = arterials
				self.streets = streets
			}
		}
	}

	/// Arterials are always drawn when the box is visible; everything else is the zoom-in-only grid.
	nonisolated static func isArterial(_ role: OfflineFeatureRole) -> Bool {
		role == .majorRoad || role == .mediumRoad || role == .rail || role == .boundary
	}

	/// Painter's order for stitched road layers (earlier = underneath).
	nonisolated private static let roadDrawOrder: [OfflineFeatureRole] = [.path, .minorRoad, .mediumRoad, .majorRoad, .rail, .boundary]

	/// Drop fills whose bounding box is smaller than this (meters) — invisible slivers/clutter.
	nonisolated static let defaultMinFillMeters: Double = 40
	/// Drop stitched roads shorter than this (meters) — driveway/stub clutter, no visual value.
	nonisolated static let defaultMinRoadMeters: Double = 60

	/// Decode + stitch the given tiles into render-ready shapes, with measurement stats. Shared by
	/// `updateIfNeeded` and the test/benchmark entry point so they exercise the identical pipeline.
	nonisolated static func build(
		source: OfflineTileSource,
		bounds: GeoBounds,
		tiles: [TileID],
		minFillMeters: Double = defaultMinFillMeters,
		minRoadMeters: Double = defaultMinRoadMeters
	) -> BuildResult {
		let clock = ContinuousClock()
		var polys: [OfflineMapPolygon] = []
		var rawSegmentsByRole: [OfflineFeatureRole: [[CLLocationCoordinate2D]]] = [:]
		var rawSegmentCount = 0
		var rawVertexCount = 0
		let decodeDuration = clock.measure {
			for tile in tiles {
				autoreleasepool {
					let decoded = decode(tile: tile, source: source, bounds: bounds)
					for polygon in decoded.polys where boundingMeters(polygon.coordinates) >= minFillMeters {
						polys.append(polygon)
					}
					for line in decoded.lines {
						rawSegmentsByRole[line.role, default: []].append(line.coordinates)
						rawSegmentCount += 1
						rawVertexCount += line.coordinates.count
					}
				}
			}
		}

		var lines: [OfflineMapPolyline] = []
		var counter = 0
		var stitchedVertexCount = 0
		let stitchDuration = clock.measure {
			for role in roadDrawOrder {
				guard let segments = rawSegmentsByRole[role] else { continue }
				for chain in stitch(segments) where chain.count >= 2 {
					// Boundaries aren't length-filtered (admin lines can be long but sparse).
					if role != .boundary, lengthMeters(chain) < minRoadMeters { continue }
					counter += 1
					stitchedVertexCount += chain.count
					lines.append(OfflineMapPolyline(id: "\(role)/\(counter)", role: role, coordinates: chain))
				}
			}
		}

		let stats = OfflineDecodeStats(
			tiles: tiles.count,
			zoom: tiles.first?.z ?? 0,
			polygons: polys.count,
			rawSegments: rawSegmentCount,
			stitchedRoads: lines.count,
			rawVertices: rawVertexCount,
			stitchedVertices: stitchedVertexCount,
			decode: decodeDuration,
			stitch: stitchDuration
		)
		return BuildResult(polygons: polys, polylines: lines, stats: stats)
	}

	/// Headless benchmark entry point: open the archive, pick tiles, and run the full build pipeline.
	nonisolated static func measure(
		url: URL,
		maxTiles: Int = 48,
		minFillMeters: Double = defaultMinFillMeters,
		minRoadMeters: Double = defaultMinRoadMeters
	) -> OfflineDecodeStats? {
		guard let source = OfflineTileSourceFactory.source(for: url), source.isVectorTiles,
			  let bounds = source.geographicBounds else { return nil }
		let tiles = boundsTiles(source: source, bounds: bounds, maxTiles: maxTiles)
		guard !tiles.isEmpty else { return nil }
		return build(source: source, bounds: bounds, tiles: tiles, minFillMeters: minFillMeters, minRoadMeters: minRoadMeters).stats
	}

}

// MARK: - Offline decode pipeline (pure functions, kept out of the class body for clarity/lint)

extension OfflineVectorTileProvider {

	// MARK: Geometry size helpers (for clutter filtering)

	nonisolated private static func lengthMeters(_ coordinates: [CLLocationCoordinate2D]) -> Double {
		guard coordinates.count >= 2 else { return 0 }
		var total = 0.0
		for index in 1..<coordinates.count {
			total += distanceMeters(coordinates[index - 1], coordinates[index])
		}
		return total
	}

	nonisolated private static func boundingMeters(_ coordinates: [CLLocationCoordinate2D]) -> Double {
		guard let first = coordinates.first else { return 0 }
		var minLat = first.latitude, maxLat = first.latitude
		var minLon = first.longitude, maxLon = first.longitude
		for coordinate in coordinates {
			minLat = min(minLat, coordinate.latitude); maxLat = max(maxLat, coordinate.latitude)
			minLon = min(minLon, coordinate.longitude); maxLon = max(maxLon, coordinate.longitude)
		}
		let midLat = (minLat + maxLat) / 2
		let height = (maxLat - minLat) * 111_320
		let width = (maxLon - minLon) * 111_320 * cos(midLat * .pi / 180)
		return max(height, width)
	}

	nonisolated private static func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
		let midLat = (a.latitude + b.latitude) / 2
		let dLat = (b.latitude - a.latitude) * 111_320
		let dLon = (b.longitude - a.longitude) * 111_320 * cos(midLat * .pi / 180)
		return (dLat * dLat + dLon * dLon).squareRoot()
	}

	// MARK: Stitching (merge connected segments → fewer overlays)

	/// Greedily joins segments that share an endpoint into longer polylines. SwiftUI `Map` makes one
	/// overlay per polyline, so fewer/longer polylines = far less MapKit overlay-layer work, with an
	/// identical rendered result (segments are only joined where their endpoints actually coincide).
	nonisolated private static func stitch(_ segments: [[CLLocationCoordinate2D]]) -> [[CLLocationCoordinate2D]] {
		guard segments.count > 1 else { return segments }
		struct PointKey: Hashable { let x: Int32; let y: Int32 }
		func key(_ coordinate: CLLocationCoordinate2D) -> PointKey {
			PointKey(x: Int32((coordinate.longitude * 100_000).rounded()),
					 y: Int32((coordinate.latitude * 100_000).rounded()))
		}

		var used = [Bool](repeating: false, count: segments.count)
		var endpointIndex: [PointKey: [Int]] = [:]
		for (index, segment) in segments.enumerated() {
			guard let first = segment.first, let last = segment.last else { used[index] = true; continue }
			endpointIndex[key(first), default: []].append(index)
			endpointIndex[key(last), default: []].append(index)
		}

		/// An unused segment touching `point`, oriented so its FIRST coordinate == `point`.
		func segment(touching point: CLLocationCoordinate2D) -> (index: Int, oriented: [CLLocationCoordinate2D])? {
			let pointKey = key(point)
			guard let candidates = endpointIndex[pointKey] else { return nil }
			for index in candidates where !used[index] {
				if key(segments[index].first!) == pointKey { return (index, segments[index]) }
				if key(segments[index].last!) == pointKey { return (index, segments[index].reversed()) }
			}
			return nil
		}

		var result: [[CLLocationCoordinate2D]] = []
		for start in segments.indices where !used[start] {
			used[start] = true
			var chain = segments[start]
			// Extend the tail: append segments whose start coincides with the chain's last point.
			while let next = segment(touching: chain[chain.count - 1]) {
				used[next.index] = true
				chain.append(contentsOf: next.oriented.dropFirst()) // skip the shared point
			}
			// Extend the head: prepend segments whose start coincides with the chain's first point.
			while let prev = segment(touching: chain[0]) {
				used[prev.index] = true
				// `oriented` starts at the shared point; reverse so it ENDS at it, then prepend.
				chain.insert(contentsOf: prev.oriented.reversed().dropLast(), at: 0)
			}
			result.append(chain)
		}
		return result
	}

	// MARK: Tile math

	/// All tiles covering the archive's coverage box, at the highest zoom whose tile count fits
	/// the cap. Decoded once; vectors scale to any map zoom.
	nonisolated private static func boundsTiles(source: OfflineTileSource, bounds: GeoBounds, maxTiles: Int) -> [TileID] {
		let minZoom = Int(source.tileMinZoom)
		let maxZoom = Int(source.tileMaxZoom)
		var zoom = maxZoom
		while zoom > minZoom {
			let topLeft = tileXY(lon: bounds.minLon, lat: bounds.maxLat, zoom: zoom)
			let bottomRight = tileXY(lon: bounds.maxLon, lat: bounds.minLat, zoom: zoom)
			let count = (abs(bottomRight.x - topLeft.x) + 1) * (abs(bottomRight.y - topLeft.y) + 1)
			if count <= maxTiles { break }
			zoom -= 1
		}

		let topLeft = tileXY(lon: bounds.minLon, lat: bounds.maxLat, zoom: zoom)
		let bottomRight = tileXY(lon: bounds.maxLon, lat: bounds.minLat, zoom: zoom)
		let n = 1 << zoom
		let xStart = min(topLeft.x, bottomRight.x)
		let xEnd = max(topLeft.x, bottomRight.x)
		let yStart = max(0, min(topLeft.y, bottomRight.y))
		let yEnd = min(n - 1, max(topLeft.y, bottomRight.y))
		guard yStart <= yEnd else { return [] }
		var result: [TileID] = []
		result.reserveCapacity((xEnd - xStart + 1) * (yEnd - yStart + 1))
		for x in xStart...xEnd {
			for y in yStart...yEnd {
				let wrappedX = ((x % n) + n) % n
				result.append(TileID(z: zoom, x: wrappedX, y: y))
			}
		}
		return result
	}

	nonisolated private static func tileXY(lon: Double, lat: Double, zoom: Int) -> (x: Int, y: Int) {
		let n = Double(1 << zoom)
		let x = Int(floor((lon + 180.0) / 360.0 * n))
		let latRad = lat * .pi / 180.0
		let y = Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n))
		return (x, y)
	}

	// MARK: Decode (mvt-tools → MapKit shapes)

	nonisolated private static let parkKinds: Set<String> = [
		"park", "garden", "recreation_ground", "pitch", "golf_course", "cemetery",
		"forest", "wood", "grass", "meadow", "nature_reserve", "playground"
	]

	nonisolated private static func decode(tile: TileID, source: OfflineTileSource, bounds: GeoBounds?) -> (polys: [OfflineMapPolygon], lines: [OfflineMapPolyline]) {
		guard let data = source.tileData(z: UInt8(tile.z), x: UInt32(tile.x), y: UInt32(tile.y)),
			  let vector = VectorTile(data: data, x: tile.x, y: tile.y, z: tile.z, projection: .epsg4326) else {
			return ([], [])
		}
		var polys: [OfflineMapPolygon] = []
		var lines: [OfflineMapPolyline] = []
		var counter = 0
		func nextID() -> String { counter += 1; return "\(tile.key)/\(counter)" }

		// Painter's order: parks first, then water on top, then all roads.
		for feature in vector.features(for: "landuse") {
			let kind = (feature.properties["kind"] as? String) ?? (feature.properties["pmap:kind"] as? String)
			guard let kind, parkKinds.contains(kind) else { continue } // parks only, skip generic land
			appendPolygons(feature.geometry, role: .park, bounds: bounds, into: &polys, id: nextID)
		}
		for feature in vector.features(for: "water") {
			appendPolygons(feature.geometry, role: .water, bounds: bounds, into: &polys, id: nextID)
		}
		// All roads (incl. the residential/neighborhood street grid); footpaths are still skipped.
		for feature in vector.features(for: "roads") {
			let kind = (feature.properties["kind"] as? String) ?? (feature.properties["pmap:kind"] as? String)
			let role = roadRole(kind)
			if role == .path { continue } // footways/cycleways: high count, low basemap value
			appendPolylines(feature.geometry, role: role, bounds: bounds, into: &lines, id: nextID)
		}
		// Boundaries (the neighborhood/admin outline overlay) intentionally omitted.
		return (polys, lines)
	}

	nonisolated private static func roadRole(_ kind: String?) -> OfflineFeatureRole {
		switch kind {
		case "highway", "motorway", "freeway", "major_road", "trunk", "primary": return .majorRoad
		case "medium_road", "secondary", "tertiary": return .mediumRoad
		case "path", "footway", "cycleway", "track": return .path
		case "rail": return .rail
		default: return .minorRoad
		}
	}

	nonisolated private static func coord(_ coordinate: GISTools.Coordinate3D) -> CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
	}

	// GISTools geometry types are fully qualified: the app target has its own `Polygon`/`Point`.
	/// Douglas–Peucker tolerance (~9m). Drops redundant vertices so each overlay is cheaper for
	/// MapKit to diff and redraw, without visibly changing shapes at basemap scale.
	nonisolated private static let simplifyEpsilon = 0.00008

	nonisolated private static func appendPolygons(_ geometry: GISTools.GeoJsonGeometry, role: OfflineFeatureRole, bounds: GeoBounds?, into polys: inout [OfflineMapPolygon], id: () -> String) {
		func add(_ ring: [GISTools.Coordinate3D]) {
			var coords = ring.map(coord)
			if let bounds { coords = clipPolygon(coords, to: bounds) }
			coords = simplify(coords, epsilon: simplifyEpsilon)
			guard coords.count >= 3 else { return }
			polys.append(OfflineMapPolygon(id: id(), role: role, coordinates: coords))
		}
		switch geometry {
		case let polygon as GISTools.Polygon:
			if let outer = polygon.rings.first?.coordinates { add(outer) }
		case let multi as GISTools.MultiPolygon:
			for polygon in multi.polygons {
				if let outer = polygon.rings.first?.coordinates { add(outer) }
			}
		default:
			break
		}
	}

	nonisolated private static func appendPolylines(_ geometry: GISTools.GeoJsonGeometry, role: OfflineFeatureRole, bounds: GeoBounds?, into lines: inout [OfflineMapPolyline], id: () -> String) {
		func add(_ line: [GISTools.Coordinate3D]) {
			let coords = line.map(coord)
			let runs = bounds.map { clipPolyline(coords, to: $0) } ?? [coords]
			for run in runs {
				let simplified = simplify(run, epsilon: simplifyEpsilon)
				if simplified.count >= 2 {
					lines.append(OfflineMapPolyline(id: id(), role: role, coordinates: simplified))
				}
			}
		}
		switch geometry {
		case let line as GISTools.LineString:
			add(line.coordinates)
		case let multi as GISTools.MultiLineString:
			for line in multi.lineStrings { add(line.coordinates) }
		default:
			break
		}
	}

	// MARK: Simplification

	/// Iterative Douglas–Peucker — drops vertices that are within `epsilon` of the line they'd lie
	/// on, so overlays carry far fewer points. Runs once at decode time (off the main thread).
	nonisolated private static func simplify(_ points: [CLLocationCoordinate2D], epsilon: Double) -> [CLLocationCoordinate2D] {
		guard points.count > 2 else { return points }
		var keep = [Bool](repeating: false, count: points.count)
		keep[0] = true
		keep[points.count - 1] = true
		var stack: [(Int, Int)] = [(0, points.count - 1)]
		while let (first, last) = stack.popLast() {
			guard last > first + 1 else { continue }
			var maxDistance = 0.0
			var maxIndex = first
			for index in (first + 1)..<last {
				let distance = perpendicularDistance(points[index], points[first], points[last])
				if distance > maxDistance {
					maxDistance = distance
					maxIndex = index
				}
			}
			if maxDistance > epsilon {
				keep[maxIndex] = true
				stack.append((first, maxIndex))
				stack.append((maxIndex, last))
			}
		}
		var result: [CLLocationCoordinate2D] = []
		for index in points.indices where keep[index] { result.append(points[index]) }
		return result
	}

	nonisolated private static func perpendicularDistance(_ point: CLLocationCoordinate2D, _ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D) -> Double {
		let dx = end.longitude - start.longitude
		let dy = end.latitude - start.latitude
		if dx == 0, dy == 0 {
			return hypot(point.longitude - start.longitude, point.latitude - start.latitude)
		}
		let t = ((point.longitude - start.longitude) * dx + (point.latitude - start.latitude) * dy) / (dx * dx + dy * dy)
		let projectedX = start.longitude + t * dx
		let projectedY = start.latitude + t * dy
		return hypot(point.longitude - projectedX, point.latitude - projectedY)
	}

	// MARK: Clipping to the coverage box

	/// Sutherland–Hodgman polygon clip against the archive's axis-aligned coverage box.
	nonisolated private static func clipPolygon(_ coords: [CLLocationCoordinate2D], to bounds: GeoBounds) -> [CLLocationCoordinate2D] {
		guard coords.count >= 3 else { return [] }
		var poly = coords
		poly = clipEdge(poly, inside: { $0.longitude >= bounds.minLon }, cross: { lerpLon($0, $1, bounds.minLon) })
		poly = clipEdge(poly, inside: { $0.longitude <= bounds.maxLon }, cross: { lerpLon($0, $1, bounds.maxLon) })
		poly = clipEdge(poly, inside: { $0.latitude >= bounds.minLat }, cross: { lerpLat($0, $1, bounds.minLat) })
		poly = clipEdge(poly, inside: { $0.latitude <= bounds.maxLat }, cross: { lerpLat($0, $1, bounds.maxLat) })
		return poly
	}

	nonisolated private static func clipEdge(
		_ poly: [CLLocationCoordinate2D],
		inside: (CLLocationCoordinate2D) -> Bool,
		cross: (CLLocationCoordinate2D, CLLocationCoordinate2D) -> CLLocationCoordinate2D
	) -> [CLLocationCoordinate2D] {
		guard poly.count >= 3 else { return [] }
		var output: [CLLocationCoordinate2D] = []
		for index in poly.indices {
			let current = poly[index]
			let previous = poly[(index + poly.count - 1) % poly.count]
			let currentInside = inside(current)
			let previousInside = inside(previous)
			if currentInside {
				if !previousInside { output.append(cross(previous, current)) }
				output.append(current)
			} else if previousInside {
				output.append(cross(previous, current))
			}
		}
		return output
	}

	/// Liang–Barsky polyline clip — returns the inside runs (a line can enter/exit the box).
	nonisolated private static func clipPolyline(_ coords: [CLLocationCoordinate2D], to bounds: GeoBounds) -> [[CLLocationCoordinate2D]] {
		guard coords.count >= 2 else { return [] }
		var runs: [[CLLocationCoordinate2D]] = []
		var current: [CLLocationCoordinate2D] = []
		func flush() {
			if current.count >= 2 { runs.append(current) }
			current = []
		}
		for index in 0..<(coords.count - 1) {
			let start = coords[index]
			let end = coords[index + 1]
			guard let (t0, t1) = liangBarsky(start, end, bounds) else { flush(); continue }
			let entry = lerp(start, end, t0)
			let exit = lerp(start, end, t1)
			if t0 > 0 { flush(); current = [entry] } else if current.isEmpty { current = [entry] }
			current.append(exit)
			if t1 < 1 { flush() }
		}
		flush()
		return runs
	}

	nonisolated private static func liangBarsky(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D, _ bounds: GeoBounds) -> (Double, Double)? {
		let dx = end.longitude - start.longitude
		let dy = end.latitude - start.latitude
		var t0 = 0.0
		var t1 = 1.0
		let checks: [(Double, Double)] = [
			(-dx, start.longitude - bounds.minLon),
			(dx, bounds.maxLon - start.longitude),
			(-dy, start.latitude - bounds.minLat),
			(dy, bounds.maxLat - start.latitude)
		]
		for (p, q) in checks {
			if p == 0 {
				if q < 0 { return nil } // parallel and outside
			} else {
				let r = q / p
				if p < 0 {
					if r > t1 { return nil }
					if r > t0 { t0 = r }
				} else {
					if r < t0 { return nil }
					if r < t1 { t1 = r }
				}
			}
		}
		return (t0, t1)
	}

	nonisolated private static func lerp(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D, _ t: Double) -> CLLocationCoordinate2D {
		CLLocationCoordinate2D(
			latitude: start.latitude + t * (end.latitude - start.latitude),
			longitude: start.longitude + t * (end.longitude - start.longitude)
		)
	}

	nonisolated private static func lerpLon(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D, _ lon: Double) -> CLLocationCoordinate2D {
		let denominator = end.longitude - start.longitude
		let t = denominator == 0 ? 0 : (lon - start.longitude) / denominator
		return CLLocationCoordinate2D(latitude: start.latitude + t * (end.latitude - start.latitude), longitude: lon)
	}

	nonisolated private static func lerpLat(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D, _ lat: Double) -> CLLocationCoordinate2D {
		let denominator = end.latitude - start.latitude
		let t = denominator == 0 ? 0 : (lat - start.latitude) / denominator
		return CLLocationCoordinate2D(latitude: lat, longitude: start.longitude + t * (end.longitude - start.longitude))
	}
}

/// SwiftUI `MapContent` for the decoded offline vector shapes. Drop into a `Map { }` builder
/// before the node content so nodes draw on top. Colors resolve per appearance.
struct OfflineVectorMapContent: MapContent {
	let polygons: [OfflineMapPolygon]
	/// Major/medium roads + rail — shown whenever the box is on screen.
	let arterials: [OfflineMapPolyline]
	/// Residential street grid — shown only when zoomed into a neighborhood (level-of-detail).
	let streets: [OfflineMapPolyline]
	let coverageBounds: GeoBounds?
	/// When false, only the cheap border + label draw; the heavy fills/roads are skipped so the
	/// thousands of overlays only exist while the coverage box is actually on screen.
	let showDetail: Bool
	/// Add the residential street grid (true only at street zoom).
	let showMinorRoads: Bool
	/// Use bolder arterial widths at city-overview zoom so they punch through the dense scene.
	let roadsWide: Bool
	let dark: Bool

	private var coverageCorners: [CLLocationCoordinate2D]? {
		guard let bounds = coverageBounds else { return nil }
		return [
			CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon),
			CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.maxLon),
			CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon),
			CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.minLon)
		]
	}

	/// Top-center of the coverage box, where the "OFFLINE MAP" tab sits.
	private var labelCoordinate: CLLocationCoordinate2D? {
		guard let bounds = coverageBounds else { return nil }
		return CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: (bounds.minLon + bounds.maxLon) / 2)
	}

	private var accent: Color { dark ? Color.cyan : Color.blue }

	@MapContentBuilder
	var body: some MapContent {
		// Heavy content only while the coverage box is on screen (see showDetail) — bounds the
		// overlay count (and its memory) to when you're actually looking at the offline area.
		if showDetail {
			// Base "earth" fill for the whole coverage box, so gaps between features read as land.
			if let corners = coverageCorners {
				MapPolygon(coordinates: corners)
					.foregroundStyle(Self.earthColor(dark: dark))
			}
			// Water/park fills (individual — far fewer than roads).
			ForEach(polygons) { polygon in
				MapPolygon(coordinates: polygon.coordinates)
					.foregroundStyle(Self.fillColor(polygon.role, dark: dark))
			}
			// Residential street grid first (underneath), only when zoomed into a neighborhood.
			if showMinorRoads {
				ForEach(streets) { line in
					MapPolyline(coordinates: line.coordinates)
						.stroke(Self.strokeColor(line.role, dark: dark), lineWidth: Self.lineWidth(line.role, wide: false))
				}
			}
			// Arterials on top — bold at city zoom so the road skeleton is instantly legible.
			ForEach(arterials) { line in
				MapPolyline(coordinates: line.coordinates)
					.stroke(Self.strokeColor(line.role, dark: dark), lineWidth: Self.lineWidth(line.role, wide: roadsWide))
			}
		}
		// Coverage rectangle — thick accent border, like the mockup (always shown, cheap).
		if let corners = coverageCorners {
			MapPolyline(coordinates: corners + [corners[0]])
				.stroke(accent, style: StrokeStyle(lineWidth: 5, lineJoin: .round))
		}
		// "OFFLINE MAP" tab centered on the top border.
		if let labelCoordinate {
			Annotation("", coordinate: labelCoordinate, anchor: .center) {
				Text("OFFLINE MAP")
					.font(.system(size: 11, weight: .heavy))
					.tracking(0.5)
					.foregroundStyle(.white)
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background(Capsule().fill(accent))
					.shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
			}
			.annotationTitles(.hidden)
		}
	}

	// "Slate & Cream" palette: soft neutral earth (never pure black / stark white) so the box blends
	// into the surrounding Apple basemap; road hierarchy carried by COLOR contrast (constant-width
	// strokes can't do true casing) — warm arterials, near-white collectors, recessive gray streets.
	private static func earthColor(dark: Bool) -> Color {
		dark ? Color(red: 0.180, green: 0.180, blue: 0.190) : Color(red: 0.940, green: 0.935, blue: 0.920)
	}

	private static func fillColor(_ role: OfflineFeatureRole, dark: Bool) -> Color {
		switch role {
		case .water:
			return dark ? Color(red: 0.160, green: 0.220, blue: 0.300) : Color(red: 0.680, green: 0.800, blue: 0.920)
		case .park, .green:
			return dark ? Color(red: 0.170, green: 0.235, blue: 0.185) : Color(red: 0.830, green: 0.890, blue: 0.795)
		case .land:
			return dark ? Color(red: 0.185, green: 0.185, blue: 0.195) : Color(red: 0.925, green: 0.920, blue: 0.905)
		default:
			return .clear
		}
	}

	private static func strokeColor(_ role: OfflineFeatureRole, dark: Bool) -> Color {
		switch role {
		case .majorRoad:
			return dark ? Color(red: 0.960, green: 0.860, blue: 0.620) : Color(red: 0.980, green: 0.760, blue: 0.330)
		case .mediumRoad:
			return dark ? Color(red: 0.880, green: 0.880, blue: 0.900) : Color(red: 1.000, green: 1.000, blue: 1.000)
		case .minorRoad:
			return dark ? Color(red: 0.610, green: 0.620, blue: 0.650) : Color(red: 0.730, green: 0.730, blue: 0.715)
		case .path:
			return dark ? Color(white: 0.43) : Color(white: 0.70)
		case .rail:
			return dark ? Color(red: 0.500, green: 0.520, blue: 0.560) : Color(red: 0.560, green: 0.580, blue: 0.620)
		case .boundary:
			return dark ? Color(red: 0.520, green: 0.470, blue: 0.580) : Color(red: 0.560, green: 0.510, blue: 0.610)
		default:
			return .clear
		}
	}

	/// `wide` is true at city-overview zoom, where arterials are the only roads drawn and must punch
	/// through; false at street zoom where the full grid is on screen and base widths keep it clean.
	private static func lineWidth(_ role: OfflineFeatureRole, wide: Bool) -> Double {
		switch role {
		case .majorRoad: return wide ? 5.5 : 4.5
		case .mediumRoad: return wide ? 3.2 : 2.8
		case .minorRoad: return 1.6
		case .path: return 1.0
		case .rail: return 1.3
		case .boundary: return 1.2
		default: return 1.0
		}
	}
}
