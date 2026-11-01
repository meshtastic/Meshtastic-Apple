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
import UIKit
import Combine

// MARK: - Native vector rendering of offline MVT tiles (drawn IN a SwiftUI Map)
//
// Instead of rasterizing the Protomaps vector tiles to PNG (MKTileOverlay), decode them with
// mvt-tools straight into native MapKit shapes (MapPolygon/MapPolyline). SwiftUI's `Map` can't host
// raster tiles, but it renders vector `MapContent` natively — so the offline basemap composites
// directly with the map's own annotations (nodes), with Apple Maps as the surrounding basemap.
// This avoids a second map, rasterization, occlusion, and the two layers drifting apart during
// camera moves.

/// Semantic role for an offline vector feature, mapped to a color/width at render time so a single
/// decode serves both light and dark appearance.
enum OfflineFeatureRole {
	case water, park, green, land, river
	case majorRoad, mediumRoad, minorRoad, path, rail, boundary
}

struct OfflineMapPolygon: Identifiable {
	/// From the map feature's own id when it has one (`role/featureID/part`), so the same
	/// feature has the same id on every build; otherwise `tile/counter`.
	var id: String
	let role: OfflineFeatureRole
	let coordinates: [CLLocationCoordinate2D]
	/// Interior rings (holes) — islands in a lake, clearings in a park. Rendered
	/// via MKPolygon(interiorPolygons:); dropping them floods islands solid.
	var interiorRings: [[CLLocationCoordinate2D]] = []
	/// Where this piece came from, for telling copies of one feature apart while decoding.
	var origin: OfflineFeatureOrigin?
}

struct OfflineMapPolyline: Identifiable {
	/// From the smallest map feature id among the segments stitched into it, when they have
	/// ids (`role/featureID`); otherwise `role/cCounter`.
	var id: String
	let role: OfflineFeatureRole
	let coordinates: [CLLocationCoordinate2D]
	/// The map feature this segment came from, while decoding.
	var featureID: UInt64?
	/// The basemap's `min_zoom`; for a stitched line, the highest of its segments'. 0 when absent.
	var minZoom: Double = 0
	/// Whether a road runs in a tunnel, on a bridge or on the ground. Stitched only with its own kind.
	var structure: OfflineRoadStructure = .surface
	/// The basemap's `sort_rank`, the importance it gives the road. For a stitched road, the
	/// highest of its segments'. Lines come out in this order; the maps draw each road class and
	/// structure as one batch of one style, so it doesn't change what they draw.
	var sortRank = 0
}

/// Where a road runs, in drawing order: tunnels under everything, bridges over the other roads.
enum OfflineRoadStructure: Int, CaseIterable, Comparable {
	case tunnel, surface, bridge

	static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Which feature a decoded polygon belongs to and which tile it was read from. A feature near a
/// tile edge is in both tiles (the neighbor carries it in its buffer), so this is what finds the
/// copies.
struct OfflineFeatureOrigin {
	/// The vector tile's feature id. Protomaps encodes the OSM element type above bit 44 and the
	/// OSM id below, so it is unique across nodes, ways and relations.
	let featureID: UInt64
	/// The polygon's index within a multipolygon feature, counted within its tile.
	let part: Int
	let tile: String
	/// The tile this piece was read from.
	let tileBounds: GeoBounds
	/// The outer ring's box as the tile stored it, buffer included.
	let ringBounds: GeoBounds
}

/// A name to print on the offline map: a place (city, town, neighborhood) or a body of water, from
/// the basemap's `places` and `water` layers.
struct OfflineMapLabel: Sendable, Equatable {
	enum Kind: Int, Sendable, Comparable {
		// In order of importance: a city wins a spot over a town, a town over a lake.
		case region, city, town, water, village, suburb, neighborhood

		static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
	}

	let name: String
	let coordinate: CLLocationCoordinate2D
	let kind: Kind
	/// The basemap's `min_zoom`: the label is printed from this map zoom on.
	let minZoom: Double
	/// The basemap's `population_rank` (0–15): bigger places first within a kind.
	let rank: Int

	/// The same label decoded from two tiles has the same key.
	var key: String { "\(kind.rawValue)|\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }

	static func == (lhs: OfflineMapLabel, rhs: OfflineMapLabel) -> Bool { lhs.key == rhs.key }

	/// Most important first: the lowest `min_zoom` (shown from furthest out), then the bigger
	/// population, then the bigger kind of place, then by name so the order is stable.
	static func ranked(_ labels: [OfflineMapLabel]) -> [OfflineMapLabel] {
		labels.sorted { ($0.minZoom, -$0.rank, $0.kind, $0.name) < ($1.minZoom, -$1.rank, $1.kind, $1.name) }
	}
}

/// Region identity required to bind an archive consistently before and after the manager loads.
struct OfflineVectorSourceBinding: Equatable {
	let url: URL
	let regionID: UUID

	init(regionFile: OfflineMapRegionFile) {
		url = regionFile.url
		regionID = regionFile.region.id
	}

	init(url: URL, regionID: UUID = UUID()) {
		self.url = url
		self.regionID = regionID
	}
}

/// Render-ready offline content plus measurement stats (returned by `OfflineVectorTileProvider.build`).
struct BuildResult {
	let polygons: [OfflineMapPolygon]
	let polylines: [OfflineMapPolyline]
	var labels: [OfflineMapLabel] = []
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
	/// Place and water names, most important first (see `OfflineMapLabel.ranked`).
	@Published private(set) var labels: [OfflineMapLabel] = []
	/// Bumped once each time a decode publishes, so observers rebuild exactly once per decode.
	@Published private(set) var revision = 0

	private(set) var isAvailable = false
	/// Coverage box for each loaded archive (for the base fills + coverage rectangles). One per region.
	private(set) var coverageAreas: [GeoBounds] = []
	/// One opened vector archive + its coverage box.
	private struct VectorSource {
		let url: URL
		let source: OfflineTileSource
		let bounds: GeoBounds
	}
	private var vectorSources: [VectorSource] = []
	/// Region identities the provider is currently bound to, so metadata changes reload even when URLs match.
	private var loadedBindings: [OfflineVectorSourceBinding] = []
	private let queue = DispatchQueue(label: "offline.vector.decode", qos: .userInitiated)
	private var didLoad = false
	/// Bumped by every reload, so a decode of the sources it replaced doesn't publish.
	private var generation = 0
	private var regionObserver: AnyCancellable?

	/// `tiles(...)` picks the highest fixed zoom whose tile count fits this cap. Residential
	/// streets only exist in Protomaps tiles at z13+, so ~48 lands on z14 (full street grid).
	private let maxTiles = 48

	struct TileID {
		let z, x, y: Int
		var key: String { "\(z)/\(x)/\(y)" }
	}

	init(bindings: [OfflineVectorSourceBinding] = OfflineVectorTileProvider.defaultBindings) {
		applySources(bindings: bindings)
		regionObserver = OfflineMapManager.shared.$regions
			.dropFirst()
			.receive(on: RunLoop.main)
			.sink { [weak self] regions in
				self?.reloadDownloadedRegions(regions)
			}
	}

	private func reloadDownloadedRegions(_ regions: [OfflineMapRegion]) {
		reload(regions: regions)
	}

	/// (Re)bind to the set of downloaded street archives, opening each vector source.
	private func applySources(bindings: [OfflineVectorSourceBinding]) {
		var result: [VectorSource] = []
		for binding in bindings {
			let url = binding.url
			if let src = OfflineTileSourceFactory.source(for: url), src.isVectorTiles, let bounds = src.geographicBounds {
				result.append(VectorSource(url: url, source: src, bounds: bounds))
			}
		}
		vectorSources = result
		isAvailable = !result.isEmpty
		coverageAreas = result.map { $0.bounds }
		loadedBindings = bindings
	}

	/// Switch to a different set of archives (e.g. after a new download) and re-decode. Both URL and
	/// persisted region identity participate in the no-op check, so a cold-start metadata correction reloads.
	func reload(regions: [OfflineMapRegion]) {
		let files = regions.compactMap { region -> OfflineMapRegionFile? in
			guard let url = OfflineMapManager.shared.fileURL(for: region) else { return nil }
			return OfflineMapRegionFile(region: region, url: url)
		}
		reload(bindings: Self.sourceBindings(for: files))
	}

	func reload(bindings: [OfflineVectorSourceBinding]) {
		guard Self.requiresReload(from: loadedBindings, to: bindings) else { return }
		applySources(bindings: bindings)
		generation += 1
		didLoad = false
		polygons = []
		roads = []
		labels = []
		revision += 1   // drop the old overlays now; the decode publishes the merged new set
		// NOTE: does NOT decode here — the caller decodes lazily (only when a region is on screen).
	}

	nonisolated static var defaultBindings: [OfflineVectorSourceBinding] {
		sourceBindings(for: OfflineMapManager.persistedRegionFiles())
	}

	nonisolated static func sourceBindings(for regionFiles: [OfflineMapRegionFile]) -> [OfflineVectorSourceBinding] {
		regionFiles.map(OfflineVectorSourceBinding.init(regionFile:))
	}

	nonisolated static func requiresReload(
		from current: [OfflineVectorSourceBinding],
		to incoming: [OfflineVectorSourceBinding]
	) -> Bool {
		current != incoming
	}

	/// Decode the whole coverage box ONCE at a fixed detail zoom, stitch road segments per role, and
	/// publish a single time. Vector geometry is resolution-independent, so it renders at every map
	/// zoom with no reload (no flashing). Decoded once and never replaced — no per-pan overlay churn.
	func updateIfNeeded() {
		guard !didLoad, !vectorSources.isEmpty else { return }
		didLoad = true
		let snapshot = vectorSources
		let cap = maxTiles
		let thisGeneration = generation
		queue.async { [weak self] in
			var allPolygons: [OfflineMapPolygon] = []
			var allRoads: [OfflineMapPolyline] = []
			var allLabels: [OfflineMapLabel] = []
			var labelKeys: Set<String> = []
			for (index, entry) in snapshot.enumerated() {
				let tiles = Self.tiles(
					bounds: entry.bounds,
					minZoom: Int(entry.source.tileMinZoom),
					maxZoom: Int(entry.source.tileMaxZoom),
					maxTiles: cap
				)
				guard !tiles.isEmpty else { continue }
				let result = Self.build(source: entry.source, bounds: entry.bounds, tiles: tiles)
				Logger.services.info("📦 [Offline] region \(index): \(result.stats.description)")
				// Namespace ids per source so merged overlays never collide in the map's id-diff.
				// Rebuilding the polygon here used to drop its holes, flooding islands and clearings.
				allPolygons.append(contentsOf: result.polygons.map { polygon in
					var namespaced = polygon
					namespaced.id = "\(index)/\(polygon.id)"
					return namespaced
				})
				// All road classes (incl. the residential grid); footways were already dropped at decode.
				allRoads.append(contentsOf: result.polylines.map { line in
					var namespaced = line
					namespaced.id = "\(index)/\(line.id)"
					return namespaced
				})
				// Overlapping regions carry the same names.
				allLabels += result.labels.filter { labelKeys.insert($0.key).inserted }
			}
			let rankedLabels = OfflineMapLabel.ranked(allLabels)
			Task { @MainActor [weak self] in
				// A reload while this ran replaced the sources: this result is for the old ones.
				guard let self, self.generation == thisGeneration else { return }
				self.polygons = allPolygons
				self.roads = allRoads
				self.labels = rankedLabels
				self.revision += 1
			}
		}
	}

	/// Rail and waterways whose `min_zoom` is above this are drawn only from this zoom on, so a
	/// zoomed-out map isn't covered in sidings and small streams. Roads already thin by zoom
	/// through their widths (see `OfflineMapPalette.roadWidthStops`).
	nonisolated static let farBandZoom: Double = 11

	/// Whether a line with this `min_zoom` shows below `farBandZoom`.
	nonisolated static func isFar(minZoom: Double) -> Bool { minZoom <= farBandZoom }

	/// Painter's order for stitched road layers (earlier = underneath).
	nonisolated private static let roadDrawOrder: [OfflineFeatureRole] = [.river, .path, .minorRoad, .mediumRoad, .majorRoad, .rail, .boundary]

	/// Drop fills whose bounding box is smaller than this (meters) — invisible slivers/clutter.
	nonisolated static let defaultMinFillMeters: Double = 40
	/// Drop stitched roads shorter than this (meters) — driveway/stub clutter, no visual value.
	nonisolated static let defaultMinRoadMeters: Double = 60

	/// Decode + stitch the given tiles into render-ready shapes, with measurement stats. Shared by
	/// `updateIfNeeded` and the test/benchmark entry point so they exercise the identical pipeline.
	/// `shouldStop` is checked before each tile; once it returns true the rest are skipped.
	nonisolated static func build(
		source: OfflineTileSource,
		bounds: GeoBounds,
		tiles: [TileID],
		minFillMeters: Double = defaultMinFillMeters,
		minRoadMeters: Double = defaultMinRoadMeters,
		shouldStop: () -> Bool = { false }
	) -> BuildResult {
		let clock = ContinuousClock()
		var polys: [OfflineMapPolygon] = []
		var rawSegmentsByRole: [OfflineFeatureRole: [OfflineMapPolyline]] = [:]
		var rawSegmentCount = 0
		var rawVertexCount = 0
		var labels: [OfflineMapLabel] = []
		var labelKeys: Set<String> = []
		let decodeDuration = clock.measure {
			for tile in tiles {
				if shouldStop() { break }
				autoreleasepool {
					let decoded = decode(tile: tile, source: source, bounds: bounds)
					for polygon in decoded.polys where boundingMeters(polygon.coordinates) >= minFillMeters {
						polys.append(polygon)
					}
					// A label near a tile edge is repeated in the neighbor's buffer.
					for label in decoded.labels where labelKeys.insert(label.key).inserted {
						labels.append(label)
					}
					for line in decoded.lines {
						rawSegmentsByRole[line.role, default: []].append(line)
						rawSegmentCount += 1
						rawVertexCount += line.coordinates.count
					}
				}
			}
			polys = identified(polys)
		}

		var lines: [OfflineMapPolyline] = []
		var counter = 0
		var usedIDs: [String: Int] = [:]
		var stitchedVertexCount = 0
		let stitchDuration = clock.measure {
			for role in roadDrawOrder {
				guard let allSegments = rawSegmentsByRole[role] else { continue }
				// A bridge or tunnel is stitched apart from the road it carries on from.
				for structure in OfflineRoadStructure.allCases {
					let roleSegments = allSegments.filter { $0.structure == structure }
					for whole in stitch(roleSegments.map(\.coordinates)) where whole.coordinates.count >= 2 {
						// Length is judged on the whole line, before it's split by band: two short pieces
						// either side of zoom 11 make one line long enough to keep.
						// Boundaries aren't length-filtered (admin lines can be long but sparse).
						if role != .boundary, lengthMeters(whole.coordinates) < minRoadMeters { continue }
						// Stitched again per band, so a line shown zoomed out never joins one that isn't.
						let members = whole.members.map { roleSegments[$0] }
						let bands = [members.filter { isFar(minZoom: $0.minZoom) }, members.filter { !isFar(minZoom: $0.minZoom) }]
						for segments in bands where !segments.isEmpty {
							for chain in stitch(segments.map(\.coordinates)) where chain.coordinates.count >= 2 {
								stitchedVertexCount += chain.coordinates.count
								let id: String
								if let featureID = chain.members.compactMap({ segments[$0].featureID }).min() {
									// A way can end up in two chains (its pieces in two tiles didn't meet).
									let base = "\(role)/\(featureID)"
									let seen = usedIDs[base, default: 0]
									usedIDs[base] = seen + 1
									id = seen == 0 ? base : "\(base)#\(seen)"
								} else {
									counter += 1
									id = "\(role)/c\(counter)"
								}
								var line = OfflineMapPolyline(id: id, role: role, coordinates: chain.coordinates)
								line.minZoom = chain.members.map { segments[$0].minZoom }.max() ?? 0
								line.structure = structure
								line.sortRank = chain.members.map { segments[$0].sortRank }.max() ?? 0
								lines.append(line)
							}
						}
					}
				}
			}
			// Lowest sort_rank first, ties in their order, so the output order is the basemap's.
			lines = lines.enumerated()
				.sorted { ($0.element.sortRank, $0.offset) < ($1.element.sortRank, $1.offset) }
				.map(\.element)
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
		return BuildResult(polygons: polys, polylines: lines, labels: labels, stats: stats)
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
		let tiles = tiles(
			bounds: bounds,
			minZoom: Int(source.tileMinZoom),
			maxZoom: Int(source.tileMaxZoom),
			maxTiles: maxTiles
		)
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
	/// A stitched road and the indices of the segments it was made from.
	struct StitchedChain {
		var coordinates: [CLLocationCoordinate2D]
		var members: [Int]
	}

	nonisolated private static func stitch(_ segments: [[CLLocationCoordinate2D]]) -> [StitchedChain] {
		guard segments.count > 1 else { return segments.indices.map { StitchedChain(coordinates: segments[$0], members: [$0]) } }
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

		var result: [StitchedChain] = []
		for start in segments.indices where !used[start] {
			used[start] = true
			var chain = segments[start]
			var members = [start]
			// Extend the tail: append segments whose start coincides with the chain's last point.
			while let next = segment(touching: chain[chain.count - 1]) {
				used[next.index] = true
				members.append(next.index)
				chain.append(contentsOf: next.oriented.dropFirst()) // skip the shared point
			}
			// Extend the head: prepend segments whose start coincides with the chain's first point.
			while let prev = segment(touching: chain[0]) {
				used[prev.index] = true
				members.append(prev.index)
				// `oriented` starts at the shared point; reverse so it ENDS at it, then prepend.
				chain.insert(contentsOf: prev.oriented.reversed().dropLast(), at: 0)
			}
			result.append(StitchedChain(coordinates: chain, members: members))
		}
		return result
	}

	// MARK: Tile math

	/// All tiles covering the archive's coverage box at the highest zoom whose tile count fits the cap.
	/// Decoded once; vectors scale to any map zoom.
	nonisolated static func tiles(
		bounds: GeoBounds,
		minZoom: Int,
		maxZoom: Int,
		maxTiles: Int = 48
	) -> [TileID] {
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

	nonisolated private static func parse(tile: TileID, source: OfflineTileSource) -> VectorTile? {
		guard let data = source.tileData(z: UInt8(tile.z), x: UInt32(tile.x), y: UInt32(tile.y)) else { return nil }
		return VectorTile(data: data, x: tile.x, y: tile.y, z: tile.z, projection: .epsg4326)
	}

	/// The water bodies in one tile, clipped to `bounds`. The spatial map paints these onto its
	/// offline texture.
	nonisolated static func waterPolygons(tile: TileID, source: OfflineTileSource, clippedTo bounds: GeoBounds?) -> [OfflineMapPolygon] {
		guard let vector = parse(tile: tile, source: source) else { return [] }
		var polys: [OfflineMapPolygon] = []
		var counter = 0
		appendWater(in: vector, bounds: bounds, into: &polys) { counter += 1; return "\(tile.key)/\(counter)" }
		return polys
	}

	// The TV target doesn't build the spatial map, where SpatialBuildingFootprint lives.
	#if !os(tvOS)
	/// The building outlines in one tile with their heights in meters, each cut to the tile so a
	/// building over a tile edge isn't drawn twice. Holes are left out. The spatial map raises these.
	nonisolated static func buildings(tile: TileID, source: OfflineTileSource) -> [SpatialBuildingFootprint] {
		guard let vector = parse(tile: tile, source: source) else { return [] }
		let tileBounds = GeoBounds.tile(z: tile.z, x: tile.x, y: tile.y)
		var result: [SpatialBuildingFootprint] = []
		for feature in vector.features(for: "buildings") {
			let height = SpatialBuildingFootprint.meters(feature.properties["height"])
			let minHeight = SpatialBuildingFootprint.meters(feature.properties["min_height"]) ?? 0
			let isPart = feature.properties["kind"] as? String == "building_part"
			for rings in polygonRings(feature.geometry) {
				guard let outer = rings.first else { continue }
				let outline = clipPolygon(outer.map(coord), to: tileBounds)
				guard outline.count >= 3 else { continue }
				let holes = rings.dropFirst().map { clipPolygon($0.map(coord), to: tileBounds) }.filter { $0.count >= 3 }
				result.append(SpatialBuildingFootprint(outline: outline, height: height, minHeight: minHeight, isPart: isPart, holes: holes))
			}
		}
		return result
	}
	#endif

	/// The water layer carries every polygonal water body (ocean, lake, dock, reef, basin…).
	/// With `tile`, each polygon records its feature for deduplication across tiles.
	nonisolated private static func appendWater(in vector: VectorTile, bounds: GeoBounds?, into polys: inout [OfflineMapPolygon], id: () -> String, tile: TileID? = nil) {
		for feature in vector.features(for: "water") {
			appendPolygons(feature.geometry, role: .water, bounds: bounds, into: &polys, id: id, source: tile.flatMap { FeatureSource(feature, tile: $0) })
		}
	}

	/// What one tile decodes to.
	struct DecodedTile {
		var polys: [OfflineMapPolygon] = []
		var lines: [OfflineMapPolyline] = []
		var labels: [OfflineMapLabel] = []
	}

	nonisolated private static func decode(tile: TileID, source: OfflineTileSource, bounds: GeoBounds?) -> DecodedTile {
		guard let vector = parse(tile: tile, source: source) else { return DecodedTile() }
		var polys: [OfflineMapPolygon] = []
		var lines: [OfflineMapPolyline] = []
		var counter = 0
		func nextID() -> String { counter += 1; return "\(tile.key)/\(counter)" }

		// Painter's order: parks first, then water on top, then all roads.
		for feature in vector.features(for: "landuse") {
			let kind = (feature.properties["kind"] as? String) ?? (feature.properties["pmap:kind"] as? String)
			guard let kind, parkKinds.contains(kind) else { continue } // parks only, skip generic land
			appendPolygons(feature.geometry, role: .park, bounds: bounds, into: &polys, id: nextID, source: FeatureSource(feature, tile: tile))
		}
		appendWater(in: vector, bounds: bounds, into: &polys, id: nextID, tile: tile)
		// The water layer also carries river/stream/canal CENTERLINES as LineStrings — in
		// current basemap builds there is no separate physical_line layer, so
		// waterway lines must come from here too or narrow rivers render as land.
		for feature in vector.features(for: "water") {
			let kind = (feature.properties["kind"] as? String) ?? (feature.properties["pmap:kind"] as? String)
			if kind == "river" || kind == "stream" || kind == "canal" {
				appendPolylines(feature.geometry, role: .river, bounds: bounds, into: &lines, id: nextID, featureID: featureID(feature), minZoom: minZoom(feature))
			}
		}
		// All roads (incl. the residential/neighborhood street grid); footpaths are still skipped.
		for feature in vector.features(for: "roads") {
			let kind = (feature.properties["kind"] as? String) ?? (feature.properties["pmap:kind"] as? String)
			let kindDetail = (feature.properties["kind_detail"] as? String) ?? (feature.properties["pmap:kind_detail"] as? String)
			let role = roadRole(kind: kind, kindDetail: kindDetail)
			if role == .path { continue } // footways/cycleways: high count, low basemap value
			let first = lines.count
			appendPolylines(feature.geometry, role: role, bounds: bounds, into: &lines, id: nextID, featureID: featureID(feature), minZoom: minZoom(feature))
			let structure = roadStructure(feature.properties)
			let sortRank = number(feature.properties["sort_rank"]).flatMap { $0.isFinite ? Int(min(max($0, -100_000), 100_000)) : nil } ?? 0
			for index in first..<lines.count {
				lines[index].structure = structure
				lines[index].sortRank = sortRank
			}
		}
		// Boundaries (the neighborhood/admin outline overlay) intentionally omitted.
		return DecodedTile(polys: polys, lines: lines, labels: labels(in: vector, bounds: bounds))
	}

	/// The named places and water bodies in a tile that fall inside `bounds`.
	nonisolated static func labels(in vector: VectorTile, bounds: GeoBounds?) -> [OfflineMapLabel] {
		var result: [OfflineMapLabel] = []
		func add(_ feature: GISTools.Feature, kind: OfflineMapLabel.Kind) {
			guard let point = feature.geometry as? GISTools.Point, let name = localizedName(feature.properties) else { return }
			let coordinate = coord(point.coordinate)
			if let bounds, !(bounds.minLat...bounds.maxLat).contains(coordinate.latitude) || !(bounds.minLon...bounds.maxLon).contains(coordinate.longitude) { return }
			let minZoom = number(feature.properties["min_zoom"] ?? feature.properties["pmap:min_zoom"]) ?? 0
			let rank = labelRank(feature.properties["population_rank"] ?? feature.properties["pmap:population_rank"])
			result.append(OfflineMapLabel(name: name, coordinate: coordinate, kind: kind, minZoom: minZoom, rank: rank))
		}
		for feature in vector.features(for: "places") {
			guard let kind = placeKind(feature.properties) else { continue }
			add(feature, kind: kind)
		}
		// Lakes, bays and the sea carry a labeled point beside their polygons.
		for feature in vector.features(for: "water") where feature.geometry is GISTools.Point {
			add(feature, kind: .water)
		}
		return result
	}

	/// The label kind for a `places` feature's properties, from the current schema's `kind` and
	/// `kind_detail` or an older Protomaps basemap's `pmap:kind` and OSM `place`, which imported
	/// archives can still carry.
	nonisolated static func placeKind(_ properties: [String: Sendable]) -> OfflineMapLabel.Kind? {
		let kind = (properties["kind"] as? String) ?? (properties["pmap:kind"] as? String)
		let detail = (properties["kind_detail"] as? String) ?? (properties["pmap:kind_detail"] as? String) ?? (properties["place"] as? String)
		return placeKind(kind: kind, kindDetail: detail)
	}

	/// A population rank as a small integer. A tile is outside data: a value too big for `Int`, or
	/// not finite, would trap in a plain conversion, so it's clamped or dropped.
	nonisolated static func labelRank(_ value: Any?) -> Int {
		guard let rank = number(value), rank.isFinite else { return 0 }
		return Int(min(max(rank, -1_000), 1_000).rounded())
	}

	/// The label kind for a `places` feature; nil for countries, which are too big for the maps here.
	nonisolated static func placeKind(kind: String?, kindDetail: String?) -> OfflineMapLabel.Kind? {
		switch kind {
		case "region": return .region
		case "locality":
			switch kindDetail {
			case "city": return .city
			case "town": return .town
			default: return .village
			}
		case "macrohood": return .suburb
		case "neighbourhood": return .neighborhood
		default: return nil
		}
	}

	/// The name in the app's language when the basemap has it (`name:fr`, `name:zh-Hant`), else the
	/// local name.
	nonisolated static func localizedName(_ properties: [String: Sendable], language: Locale.Language = Locale.current.language) -> String? {
		if let code = language.languageCode?.identifier {
			if let script = language.script?.identifier, let name = properties["name:\(code)-\(script)"] as? String, !name.isEmpty { return name }
			if let name = properties["name:\(code)"] as? String, !name.isEmpty { return name }
		}
		guard let name = properties["name"] as? String, !name.isEmpty else { return nil }
		return name
	}

	/// A tile property read as a number: vector tiles store numbers as doubles or integers.
	nonisolated private static func number(_ value: Any?) -> Double? {
		switch value {
		case let number as Double: return number
		case let number as Float: return Double(number)
		case let number as Int: return Double(number)
		case let number as Int64: return Double(number)
		case let number as UInt64: return Double(number)
		default: return nil
		}
	}

	/// A road's structure from the current schema's `is_tunnel` / `is_bridge`, or an older
	/// basemap's `pmap:level` (below 0 a tunnel, above 0 a bridge).
	nonisolated static func roadStructure(_ properties: [String: Sendable]) -> OfflineRoadStructure {
		func flag(_ value: Any?) -> Bool {
			if let bool = value as? Bool { return bool }
			return (number(value) ?? 0) != 0
		}
		if flag(properties["is_tunnel"]) { return .tunnel }
		if flag(properties["is_bridge"]) { return .bridge }
		guard let level = number(properties["pmap:level"]) else { return .surface }
		return level < 0 ? .tunnel : level > 0 ? .bridge : .surface
	}

	nonisolated static func roadRole(kind: String?, kindDetail: String?) -> OfflineFeatureRole {
		if kind == "path", kindDetail == "pedestrian" { return .minorRoad }
		// The current schema has no medium kind: secondary and tertiary roads are major roads
		// with that detail.
		if kind == "major_road", kindDetail == "secondary" || kindDetail == "tertiary" { return .mediumRoad }
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

	/// A decoded feature's id and tile, for `OfflineFeatureOrigin`. Nil without a feature id.
	struct FeatureSource {
		let featureID: UInt64
		let tile: TileID

		init?(_ feature: GISTools.Feature, tile: TileID) {
			guard let featureID = OfflineVectorTileProvider.featureID(feature) else { return nil }
			self.featureID = featureID
			self.tile = tile
		}
	}

	/// The vector tile's id for a feature. mvt-tools gives a feature without one a random
	/// string, which isn't stable, so only numeric ids count.
	nonisolated static func featureID(_ feature: GISTools.Feature) -> UInt64? {
		switch feature.id {
		case .uint(let value)?: return UInt64(value)
		case .int(let value)? where value >= 0: return UInt64(value)
		default: return nil
		}
	}

	/// Drops the copies of a feature that neighboring tiles carry in their buffers. A tile holds
	/// everything inside it, so a piece from one tile lying wholly inside another tile that also has
	/// the feature is that tile's buffer copy. Anything reaching into its own tile is kept, so a
	/// part of a multipolygon that only one tile has is never lost, and a feature cut by a tile edge
	/// keeps each tile's piece. Geometry is never merged. Ids come from the feature id, qualified by
	/// tile when pieces from more than one tile remain.
	nonisolated static func identified(_ polygons: [OfflineMapPolygon]) -> [OfflineMapPolygon] {
		var groups: [String: [Int]] = [:]
		var order: [String] = []
		for (index, polygon) in polygons.enumerated() {
			guard let origin = polygon.origin else { continue }
			let key = "\(polygon.role)/\(origin.featureID)"
			if groups[key] == nil { order.append(key) }
			groups[key, default: []].append(index)
		}
		var result = polygons
		var keep = [Bool](repeating: true, count: polygons.count)
		for key in order {
			guard let members = groups[key] else { continue }
			var tiles: [String: GeoBounds] = [:]
			for index in members {
				if let origin = polygons[index].origin { tiles[origin.tile] = origin.tileBounds }
			}
			var kept: [Int] = []
			for index in members {
				guard let origin = polygons[index].origin else { continue }
				let isBufferCopy = tiles.contains { tile, bounds in
					tile != origin.tile && Self.contains(bounds, origin.ringBounds)
				}
				if isBufferCopy { keep[index] = false } else { kept.append(index) }
			}
			let oneTile = Set(kept.compactMap { polygons[$0].origin?.tile }).count == 1
			for index in kept {
				guard let origin = polygons[index].origin else { continue }
				result[index].id = oneTile ? "\(key)/\(origin.part)" : "\(key)/\(origin.tile)/\(origin.part)"
			}
		}
		return result.indices.filter { keep[$0] }.map { result[$0] }
	}

	/// Whether `outer` holds all of `inner`, with a hair of slack for a ring ending on the edge.
	nonisolated private static func contains(_ outer: GeoBounds, _ inner: GeoBounds) -> Bool {
		let slack = (outer.maxLon - outer.minLon) * 1e-6
		return inner.minLon >= outer.minLon - slack && inner.maxLon <= outer.maxLon + slack
			&& inner.minLat >= outer.minLat - slack && inner.maxLat <= outer.maxLat + slack
	}

	nonisolated private static func appendPolygons(_ geometry: GISTools.GeoJsonGeometry, role: OfflineFeatureRole, bounds: GeoBounds?, into polys: inout [OfflineMapPolygon], id: () -> String, source: FeatureSource? = nil) {
		let tileBounds = source.map { GeoBounds.tile(z: $0.tile.z, x: $0.tile.x, y: $0.tile.y) }
		var part = 0
		func prepared(_ ring: [GISTools.Coordinate3D]) -> [CLLocationCoordinate2D]? {
			var coords = ring.map(coord)
			if let bounds { coords = clipPolygon(coords, to: bounds) }
			coords = simplify(coords, epsilon: simplifyEpsilon)
			return coords.count >= 3 ? coords : nil
		}
		func add(_ rings: [[GISTools.Coordinate3D]]) {
			defer { part += 1 }
			guard let outerRing = rings.first, let outer = prepared(outerRing) else { return }
			// Interior rings are holes (islands in water, clearings in parks) —
			// dropping them painted islands solid blue.
			let interiors = rings.dropFirst().compactMap(prepared)
			var origin: OfflineFeatureOrigin?
			if let source, let tileBounds, let first = outerRing.first {
				var box = (minLon: first.longitude, minLat: first.latitude, maxLon: first.longitude, maxLat: first.latitude)
				for point in outerRing {
					box.minLon = min(box.minLon, point.longitude); box.maxLon = max(box.maxLon, point.longitude)
					box.minLat = min(box.minLat, point.latitude); box.maxLat = max(box.maxLat, point.latitude)
				}
				let ringBounds = GeoBounds(minLon: box.minLon, minLat: box.minLat, maxLon: box.maxLon, maxLat: box.maxLat)
				origin = OfflineFeatureOrigin(featureID: source.featureID, part: part, tile: source.tile.key, tileBounds: tileBounds, ringBounds: ringBounds)
			}
			polys.append(OfflineMapPolygon(id: id(), role: role, coordinates: outer, interiorRings: interiors, origin: origin))
		}
		for rings in polygonRings(geometry) {
			add(rings)
		}
	}

	/// A decoded polygon geometry as polygons of rings, each outer ring first and its holes after.
	///
	/// mvt-tools groups rings by a winding rule that is backwards for tiles that follow the vector
	/// tile spec, which every Protomaps build does: it starts a new polygon at each hole and files
	/// the second and later outer rings as holes. A strait came out as a hole, so it drew as land,
	/// and enclosed islands drew as water. It keeps the rings in tile order, though, and the spec
	/// makes a polygon's first ring its outer one, so they're grouped again here: rings winding like
	/// the first start a new polygon, the others are holes in the one before. That holds whichever
	/// way the encoder wound them, so tiles mvt-tools wrote itself still come out right.
	nonisolated static func polygonRings(_ geometry: GISTools.GeoJsonGeometry) -> [[[GISTools.Coordinate3D]]] {
		let rings: [[GISTools.Coordinate3D]]
		switch geometry {
		case let polygon as GISTools.Polygon:
			rings = polygon.rings.map(\.coordinates)
		case let multi as GISTools.MultiPolygon:
			rings = multi.polygons.flatMap { $0.rings.map(\.coordinates) }
		default:
			return []
		}
		guard let first = rings.first else { return [] }
		// A first ring with no area can't say: take the spec's winding, outer rings clockwise on the map.
		let firstArea = signedArea(first)
		let outerIsNegative = firstArea == 0 || firstArea < 0
		var result: [[[GISTools.Coordinate3D]]] = []
		for ring in rings {
			let area = signedArea(ring)
			if result.isEmpty || (area != 0 && (area < 0) == outerIsNegative) {
				result.append([ring])
			} else {
				result[result.count - 1].append(ring)
			}
		}
		return result
	}

	/// The shoelace sum in degrees, positive when a ring runs counter-clockwise on the map. Only its
	/// sign is used. Measured from the ring's first point: from the origin the products are around
	/// 6,000 for a ring near Seattle, and a ring a meter across loses its sign to rounding.
	nonisolated private static func signedArea(_ ring: [GISTools.Coordinate3D]) -> Double {
		guard ring.count >= 3, let origin = ring.first else { return 0 }
		var sum = 0.0
		for index in ring.indices {
			let a = ring[index], b = ring[(index + 1) % ring.count]
			let ax = a.longitude - origin.longitude, ay = a.latitude - origin.latitude
			let bx = b.longitude - origin.longitude, by = b.latitude - origin.latitude
			sum += ax * by - bx * ay
		}
		return sum
	}

	/// A feature's `min_zoom` (or an older basemap's `pmap:min_zoom`), 0 when it has none.
	nonisolated static func minZoom(_ feature: GISTools.Feature) -> Double {
		let value = number(feature.properties["min_zoom"] ?? feature.properties["pmap:min_zoom"]) ?? 0
		return value.isFinite ? value : 0
	}

	nonisolated private static func appendPolylines(_ geometry: GISTools.GeoJsonGeometry, role: OfflineFeatureRole, bounds: GeoBounds?, into lines: inout [OfflineMapPolyline], id: () -> String, featureID: UInt64? = nil, minZoom: Double = 0) {
		func add(_ line: [GISTools.Coordinate3D]) {
			let coords = line.map(coord)
			let runs = bounds.map { clipPolyline(coords, to: $0) } ?? [coords]
			for run in runs {
				let simplified = simplify(run, epsilon: simplifyEpsilon)
				if simplified.count >= 2 {
					lines.append(OfflineMapPolyline(id: id(), role: role, coordinates: simplified, featureID: featureID, minZoom: minZoom))
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

// MARK: - Offline basemap palette

/// Colors and stroke widths for the decoded offline features, approximating Apple Maps
/// Standard in light and dark. Shared so the iOS map and the tvOS map render identically.
enum OfflineMapPalette {

	static func earth(dark: Bool) -> UIColor {
		dark ? UIColor(red: 0.137, green: 0.137, blue: 0.145, alpha: 1)
			 : UIColor(red: 0.953, green: 0.945, blue: 0.929, alpha: 1)
	}

	static func fill(_ role: OfflineFeatureRole, dark: Bool) -> UIColor? {
		switch role {
		case .water: return dark ? UIColor(red: 0.094, green: 0.169, blue: 0.267, alpha: 1) : UIColor(red: 0.667, green: 0.831, blue: 0.953, alpha: 1)
		case .park, .green: return dark ? UIColor(red: 0.125, green: 0.204, blue: 0.145, alpha: 1) : UIColor(red: 0.776, green: 0.882, blue: 0.706, alpha: 1)
		case .land: return earth(dark: dark)
		default: return nil
		}
	}

	/// River/stream centerline stroke — the water fill color, fully opaque.
	static func riverStroke(dark: Bool) -> UIColor {
		fill(.water, dark: dark) ?? .systemBlue
	}

	/// Road fill: white centerline (light) or a lighter-than-land gray (dark).
	static func roadFill(_ role: OfflineFeatureRole, dark: Bool) -> UIColor? {
		switch role {
		case .majorRoad: return dark ? UIColor(red: 0.40, green: 0.40, blue: 0.43, alpha: 1) : .white
		case .mediumRoad: return dark ? UIColor(red: 0.31, green: 0.31, blue: 0.34, alpha: 1) : .white
		case .minorRoad: return dark ? UIColor(red: 0.24, green: 0.24, blue: 0.27, alpha: 1) : .white
		default: return nil
		}
	}

	/// A road in a tunnel: the casing color (light) or the road's own gray (dark), faded, drawn dashed
	/// with no casing under the rest of the roads.
	static func tunnelStroke(_ role: OfflineFeatureRole, dark: Bool) -> UIColor? {
		(roadCasing(role, dark: dark) ?? roadFill(role, dark: dark))?.withAlphaComponent(0.6)
	}

	/// Road casing (light mode only): a warm-gray outline that makes the white roads read on pale land.
	static func roadCasing(_ role: OfflineFeatureRole, dark: Bool) -> UIColor? {
		guard !dark else { return nil }
		switch role {
		case .majorRoad, .mediumRoad, .minorRoad: return UIColor(red: 0.835, green: 0.824, blue: 0.800, alpha: 1)
		default: return nil
		}
	}

	/// Road width in points at a map zoom level, as `(zoom, width)` stops. Below the first stop the
	/// road isn't drawn: streets appear at zoom 12 and medium roads at 9, so a city or region view
	/// shows the main roads and not the whole grid. Close up they widen like the roads they are.
	static func roadWidthStops(_ role: OfflineFeatureRole) -> [(zoom: Double, width: CGFloat)] {
		switch role {
		case .majorRoad: return [(5, 0.4), (9, 0.9), (12, 1.6), (15, 4), (18, 12)]
		case .mediumRoad: return [(9, 0.3), (12, 0.9), (15, 3), (18, 10)]
		case .minorRoad: return [(12, 0.3), (13, 0.6), (15, 2), (18, 9)]
		default: return [(0, 1)]
		}
	}

	/// Road width in points at `zoom`, 0 when the road isn't drawn at that zoom.
	static func roadWidth(_ role: OfflineFeatureRole, zoom: Double) -> CGFloat {
		interpolate(roadWidthStops(role), at: zoom)
	}

	/// The casing outlines a road wherever it is drawn: a hairline each side zoomed out, which keeps
	/// a thin white road visible on pale land, growing to about 0.7 pt each side by zoom 14.
	static func roadCasingWidth(_ role: OfflineFeatureRole, zoom: Double) -> CGFloat {
		let width = roadWidth(role, zoom: zoom)
		guard width > 0 else { return 0 }
		return width + interpolate([(0, 0.6), (12, 0.6), (14, 1.4)], at: zoom)
	}

	/// The width between the stops either side of `zoom`, and the last stop's past the end. 0 before
	/// the first stop.
	static func interpolate(_ stops: [(zoom: Double, width: CGFloat)], at zoom: Double) -> CGFloat {
		guard let first = stops.first, zoom >= first.zoom else { return 0 }
		for (low, high) in zip(stops, stops.dropFirst()) where zoom < high.zoom {
			let t = (zoom - low.zoom) / (high.zoom - low.zoom)
			return low.width + CGFloat(t) * (high.width - low.width)
		}
		return stops.last?.width ?? 0
	}

	/// The map zoom level for a MapKit zoom scale (screen points per map point): zoom 0 is the
	/// world in 256 points.
	static func zoomLevel(zoomScale: MKZoomScale) -> Double {
		log2(Double(zoomScale) * MKMapSize.world.width / 256)
	}

	/// Rail / admin-boundary stroke color (single dashed line, both modes).
	static func line(_ role: OfflineFeatureRole, dark: Bool) -> UIColor? {
		switch role {
		case .rail: return dark ? UIColor(red: 0.45, green: 0.46, blue: 0.49, alpha: 1) : UIColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1)
		case .boundary: return dark ? UIColor(red: 0.50, green: 0.46, blue: 0.56, alpha: 1) : UIColor(red: 0.66, green: 0.62, blue: 0.70, alpha: 1)
		default: return nil
		}
	}
}
