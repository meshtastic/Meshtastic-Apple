//
//  TerrainContourProvider.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/16/26.
//
//  Generates contour polylines for the visible map area from downloaded terrain
//  and publishes them as MapKit shapes. Mirrors OfflineVectorTileProvider's
//  shape: work happens off the main actor, results publish on it, and the
//  consumer folds the output into ClusterMapView's overlay list.
//

import Foundation
import MapKit
import OSLog

/// One published batch of contour geometry: minor and index lines batched into
/// two MKMultiPolylines so the overlay count stays constant regardless of how
/// many individual contour lines are visible.
struct TerrainContourGeometry {
	let minorLines: MKMultiPolyline
	let indexLines: MKMultiPolyline
	/// Elevation labels for the index contours (bounded count per generation).
	let labels: [TerrainContourLabel]
	/// Cache key of the tile set + intervals this geometry was built for.
	let key: String
}

/// One elevation label anchored to an index contour.
struct TerrainContourLabel: Identifiable, Equatable {
	let id: String
	let coordinate: CLLocationCoordinate2D
	let text: String

	static func == (lhs: TerrainContourLabel, rhs: TerrainContourLabel) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class TerrainContourProvider: ObservableObject {

	@Published private(set) var geometry: TerrainContourGeometry?
	/// Bumped on every publish so observers rebuild exactly once per generation.
	@Published private(set) var revision = 0

	let store: TerrainStore
	private var generation = 0
	/// The in-flight generation task; superseded or invalidated generations are
	/// cancelled so their decode work stops instead of running to a discarded end.
	private var generationTask: Task<Void, Never>?
	/// Generated ContourLine sets per tile key, so panning re-uses tiles already computed.
	private var tileCache: [String: [ContourLine]] = [:]
	private var tileCacheOrder: [String] = []
	private let tileCacheLimit = 64

	/// Contours draw from this fixed zoom band relative to the visible zoom: one
	/// generation tile covers a 2×2 block of screen tiles so the tile count per
	/// generation stays small (≤ ~12 for a full screen).
	private let maxGenerationTiles = 12

	init(store: TerrainStore = TerrainStore()) {
		self.store = store
	}

	/// Clears cached geometry (call when the underlying terrain data changes).
	func invalidate() {
		generation += 1          // an in-flight task must not publish stale geometry
		generationTask?.cancel()
		generationTask = nil
		tileCache.removeAll()
		tileCacheOrder.removeAll()
		geometry = nil
		revision += 1
	}

	/// Regenerates contours for the visible region if the covering tile set or
	/// interval band changed. Cheap when nothing changed.
	func update(region: MKCoordinateRegion, metric: Bool) {
		let zoom = Self.zoomLevel(for: region)
		// Generate at two zooms below the view so one generation covers the screen.
		let genZoom = max(4, min(zoom - 2, 15))
		let intervals = ContourIntervals.intervals(forZoom: zoom, metric: metric)
		let tiles = Self.tiles(covering: region, zoom: genZoom, limit: maxGenerationTiles)
		guard !tiles.isEmpty else { return }
		let key = "\(genZoom)|\(intervals.minor)|" + tiles.map { "\($0.x),\($0.y)" }.joined(separator: ";")
		if geometry?.key == key { return }

		generation += 1
		let thisGeneration = generation
		let store = store
		let cached = tileCache

		generationTask?.cancel()
		generationTask = Task.detached(priority: .userInitiated) { [weak self] in
			var perTile: [(tile: (z: Int, x: Int, y: Int), lines: [ContourLine])] = []
			for tile in tiles {
				if Task.isCancelled { return }
				let tileKey = "\(genZoom)/\(tile.x)/\(tile.y)|\(intervals.minor)"
				if let lines = cached[tileKey] {
					perTile.append(((genZoom, tile.x, tile.y), lines))
					continue
				}
				guard let elevationTile = await store.elevationTile(z: genZoom, x: tile.x, y: tile.y, margin: 2) else { continue }
				let lines = ContourGenerator.contours(tile: elevationTile, intervals: intervals)
				perTile.append(((genZoom, tile.x, tile.y), lines))
			}

			// Convert tile-unit points to map coordinates and batch by class.
			var minor: [MKPolyline] = []
			var index: [MKPolyline] = []
			// One label candidate per index line, placed at the line's midpoint;
			// the longest lines win the bounded label budget.
			var labelCandidates: [(pointCount: Int, label: TerrainContourLabel)] = []
			for entry in perTile {
				let n = Double(1 << entry.tile.z)
				func coordinate(_ point: CGPoint) -> CLLocationCoordinate2D {
					let wx = (Double(entry.tile.x) + point.x) / n
					let wy = (Double(entry.tile.y) + point.y) / n
					let lon = wx * 360 - 180
					let lat = atan(sinh(.pi * (1 - 2 * wy))) * 180 / .pi
					return CLLocationCoordinate2D(latitude: lat, longitude: lon)
				}
				for (lineIndex, line) in entry.lines.enumerated() where line.points.count >= 2 {
					let coordinates = line.points.map(coordinate)
					let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
					if line.isIndex {
						index.append(polyline)
						if line.points.count >= 12 {
							let mid = coordinate(line.points[line.points.count / 2])
							labelCandidates.append((line.points.count, TerrainContourLabel(
								id: "\(entry.tile.z)/\(entry.tile.x)/\(entry.tile.y)-\(Int(line.elevation))-\(lineIndex)",
								coordinate: mid,
								text: Self.labelText(elevationMeters: line.elevation, metric: metric)
							)))
						}
					} else {
						minor.append(polyline)
					}
				}
			}
			let labels = labelCandidates
				.sorted { $0.pointCount > $1.pointCount }
				.prefix(24)
				.map(\.label)
			let built = TerrainContourGeometry(
				minorLines: MKMultiPolyline(minor),
				indexLines: MKMultiPolyline(index),
				labels: Array(labels),
				key: key
			)

			await MainActor.run { [weak self] in
				guard let self, self.generation == thisGeneration else { return }
				for entry in perTile {
					let tileKey = "\(entry.tile.z)/\(entry.tile.x)/\(entry.tile.y)|\(intervals.minor)"
					if self.tileCache[tileKey] == nil {
						self.tileCache[tileKey] = entry.lines
						self.tileCacheOrder.append(tileKey)
						if self.tileCacheOrder.count > self.tileCacheLimit {
							self.tileCache.removeValue(forKey: self.tileCacheOrder.removeFirst())
						}
					}
				}
				self.geometry = built
				self.revision += 1
			}
		}
	}

	/// "1250 m" / "4000 ft" per the user's measurement system.
	nonisolated static func labelText(elevationMeters: Double, metric: Bool) -> String {
		if metric {
			return "\(Int(elevationMeters.rounded())) m"
		}
		return "\(Int((elevationMeters / 0.3048).rounded())) ft"
	}

	// MARK: - Tiling helpers

	static func zoomLevel(for region: MKCoordinateRegion) -> Int {
		let spanDegrees = max(region.span.longitudeDelta, 0.0001)
		let zoom = log2(360 / spanDegrees) + 1
		return max(0, min(18, Int(zoom.rounded())))
	}

	static func tiles(covering region: MKCoordinateRegion, zoom: Int, limit: Int) -> [(x: Int, y: Int)] {
		let minLon = region.center.longitude - region.span.longitudeDelta / 2
		let maxLon = region.center.longitude + region.span.longitudeDelta / 2
		let minLat = region.center.latitude - region.span.latitudeDelta / 2
		let maxLat = region.center.latitude + region.span.latitudeDelta / 2
		let (x0, y0) = PMTilesExtractor.tileXY(lon: minLon, lat: maxLat, z: zoom)
		let (x1, y1) = PMTilesExtractor.tileXY(lon: maxLon, lat: minLat, z: zoom)
		var result: [(x: Int, y: Int)] = []
		for y in Int(min(y0, y1))...Int(max(y0, y1)) {
			for x in Int(min(x0, x1))...Int(max(x0, x1)) {
				result.append((x, y))
				if result.count > limit { return Array(result.prefix(limit)) }
			}
		}
		return result
	}
}
