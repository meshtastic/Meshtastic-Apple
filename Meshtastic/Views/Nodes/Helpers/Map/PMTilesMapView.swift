//
//  PMTilesMapView.swift
//  Meshtastic
//
//  Native vector rendering of an OFFLINE Protomaps `.pmtiles` archive. `OfflineVectorTileProvider`
//  decodes the MVT tiles into MapKit shapes (polygons / polylines) once per region, which the
//  MKMapView-backed map draws as overlays — so the offline basemap composites directly with the
//  map's annotations, with no rasterization and no second map.
//

import GISTools
import MapKit
import MVTTools
import OSLog
import SwiftUI

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
	/// Full road network (incl. the residential/neighborhood grid), stitched into long polylines.
	/// Rendered as a few batched MKMultiPolylines per role, so the whole grid stays smooth.
	@Published private(set) var roads: [OfflineMapPolyline] = []
	/// Bumped once each time a decode publishes, so observers rebuild exactly once per decode.
	@Published private(set) var revision = 0

	private(set) var isAvailable = false
	/// Coverage box for each loaded archive (for the base fills + coverage rectangles). One per region.
	private(set) var coverageAreas: [GeoBounds] = []
	/// One opened vector archive + its coverage box.
	private struct VectorSource { let url: URL; let source: OfflineTileSource; let bounds: GeoBounds }
	private var vectorSources: [VectorSource] = []
	/// URLs the provider is currently bound to, so reload(urls:) can no-op when unchanged.
	private var loadedURLs: [URL] = []
	private let queue = DispatchQueue(label: "offline.vector.decode", qos: .userInitiated)
	private var didLoad = false

	/// `boundsTiles` picks the highest fixed zoom whose tile count fits this cap. Residential
	/// streets only exist in Protomaps tiles at z13+, so ~48 lands on z14 (full street grid).
	private let maxTiles = 48

	struct TileID {
		let z, x, y: Int
		var key: String { "\(z)/\(x)/\(y)" }
	}

	init(urls: [URL] = OfflineVectorTileProvider.defaultURLs) {
		applySources(urls: urls)
	}

	/// (Re)bind to the set of downloaded street archives, opening each vector source.
	private func applySources(urls: [URL]) {
		var result: [VectorSource] = []
		for url in urls {
			if let src = OfflineTileSourceFactory.source(for: url), src.isVectorTiles, let bounds = src.geographicBounds {
				result.append(VectorSource(url: url, source: src, bounds: bounds))
			}
		}
		vectorSources = result
		isAvailable = !result.isEmpty
		coverageAreas = result.map { $0.bounds }
		loadedURLs = urls
	}

	/// Switch to a different set of archives (e.g. after a new download) and re-decode. No-op when the
	/// URL set is unchanged; clears the old overlays + re-decodes when it changes.
	func reload(urls: [URL]) {
		guard urls != loadedURLs else { return }
		applySources(urls: urls)
		didLoad = false
		polygons = []
		roads = []
		revision += 1   // drop the old overlays now; the decode publishes the merged new set
		// NOTE: does NOT decode here — the caller decodes lazily (only when a region is on screen).
	}

	nonisolated static var defaultURLs: [URL] {
		// All user-downloaded regions (the provider keeps only the vector ones).
		OfflineMapManager.allRegionFileURLs()
	}

	/// Decode the whole coverage box ONCE at a fixed detail zoom, stitch road segments per role, and
	/// publish a single time. Vector geometry is resolution-independent, so it renders at every map
	/// zoom with no reload (no flashing). Decoded once and never replaced — no per-pan overlay churn.
	func updateIfNeeded() {
		guard !didLoad, !vectorSources.isEmpty else { return }
		didLoad = true
		let snapshot = vectorSources
		let cap = maxTiles
		queue.async { [weak self] in
			var allPolygons: [OfflineMapPolygon] = []
			var allRoads: [OfflineMapPolyline] = []
			for (index, entry) in snapshot.enumerated() {
				let tiles = Self.boundsTiles(source: entry.source, bounds: entry.bounds, maxTiles: cap)
				guard !tiles.isEmpty else { continue }
				let result = Self.build(source: entry.source, bounds: entry.bounds, tiles: tiles)
				Logger.services.info("📦 [Offline] region \(index): \(result.stats.description)")
				// Namespace ids per source so merged overlays never collide in the map's id-diff.
				allPolygons.append(contentsOf: result.polygons.map {
					OfflineMapPolygon(id: "\(index)/\($0.id)", role: $0.role, coordinates: $0.coordinates)
				})
				// All road classes (incl. the residential grid); footways were already dropped at decode.
				for line in result.polylines {
					allRoads.append(OfflineMapPolyline(id: "\(index)/\(line.id)", role: line.role, coordinates: line.coordinates))
				}
			}
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.polygons = allPolygons
				self.roads = allRoads
				self.revision += 1
			}
		}
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

