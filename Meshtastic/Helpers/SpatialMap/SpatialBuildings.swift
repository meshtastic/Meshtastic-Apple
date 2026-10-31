//
//  SpatialBuildings.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//
import CoreLocation
import Foundation
import OSLog
import simd

/// One building from the downloaded basemap: its outline and how tall it is, in meters. Most
/// buildings in OpenStreetMap carry no height, so `height` is often nil.
struct SpatialBuildingFootprint: Sendable {
	let outline: [CLLocationCoordinate2D]
	let height: Double?
	/// Where a building part starts above the ground, for the upper floors of a tower.
	let minHeight: Double
	/// A piece of a building drawn in parts, like a tower's legs, deck and spire.
	var isPart = false
	/// Courtyards: rings inside the outline that the building doesn't cover. The mesh fills
	/// them in; they only keep a part standing in a courtyard from hiding the building.
	var holes: [[CLLocationCoordinate2D]] = []

	/// A tile property read as meters: vector tiles store numbers as doubles or integers.
	static func meters(_ value: Any?) -> Double? {
		switch value {
		case let number as Double: return number
		case let number as Float: return Double(number)
		case let number as Int: return Double(number)
		case let number as Int64: return Double(number)
		case let number as UInt64: return Double(number)
		default: return nil
		}
	}
}

/// The spatial map's Buildings option: the downloaded basemap's building outlines raised to their
/// heights and stood on the terrain, as one mesh.
enum SpatialBuildings {
	/// Most vector tiles decoded for one build. Buildings are only in the deeper zooms, so a box too
	/// big for this many tiles at zoom 13 shows none, and they would be specks at that size anyway.
	static let maxTiles = 36
	/// Protomaps puts every building in zoom 15, the bigger ones in 14 and only the largest in 13.
	static let maximumZoom = 15
	static let minimumZoom = 13
	/// For buildings with no height in the data: about two floors.
	static let defaultHeight = 6.0
	/// The biggest buildings are kept first when there are more triangles than this.
	static let triangleBudget = 300_000
	/// Buildings stand inside this share of the disk's radius, clear of the bezel.
	static let diskShare: Float = 0.98

	// MARK: Tiles

	/// The zoom to decode at: the archive's deepest up to `maximumZoom`, lowered until the box needs
	/// at most `maxTiles`. Nil when even `minimumZoom` needs more, or the archive stops above it.
	static func zoom(bounds: GeoBounds, archiveMaxZoom: Int, maxTiles: Int = maxTiles) -> Int? {
		var zoom = min(archiveMaxZoom, maximumZoom)
		while zoom >= minimumZoom {
			if SpatialOfflineMap.tiles(bounds: bounds, zoom: zoom).count <= maxTiles { return zoom }
			zoom -= 1
		}
		return nil
	}

	/// Decodes the buildings of the downloaded basemaps that touch the box, deepest archive first. A
	/// tile already inside a decoded basemap is not decoded again from an overlapping one. Nil when
	/// cancelled.
	static func decode(bounds: GeoBounds, files: [OfflineMapRegionFile] = OfflineMapManager.persistedRegionFiles()) -> [SpatialBuildingFootprint]? {
		let started = Date()
		let sources = files
			.filter { $0.region.hasBasemap && $0.region.bounds.intersects(bounds) }
			.compactMap { file -> (OfflineTileSource, GeoBounds)? in
				guard let source = OfflineTileSourceFactory.source(for: file.url), source.isVectorTiles else { return nil }
				let coverage = source.geographicBounds ?? file.region.bounds
				return coverage.intersects(bounds) ? (source, coverage) : nil
			}
			.sorted { $0.0.tileMaxZoom > $1.0.tileMaxZoom }
		var footprints: [SpatialBuildingFootprint] = []
		var decoded: [GeoBounds] = []
		var tileCount = 0
		for (source, coverage) in sources {
			if Task.isCancelled { return nil }
			guard let zoom = zoom(bounds: bounds, archiveMaxZoom: Int(source.tileMaxZoom)) else { continue }
			let tiles = SpatialOfflineMap.newTiles(SpatialOfflineMap.tiles(bounds: bounds, zoom: zoom), coverage: coverage, decoded: decoded)
			for tile in tiles {
				if Task.isCancelled { return nil }
				footprints += OfflineVectorTileProvider.buildings(tile: tile, source: source)
			}
			tileCount += tiles.count
			decoded.append(coverage)
		}
		guard let withoutOutlines = withoutOutlinesOfParts(footprints) else { return nil }
		footprints = withoutOutlines
		Logger.services.info("🧊 [Spatial] Buildings: \(footprints.count) from \(tileCount) tiles in \(String(format: "%.2f", Date().timeIntervalSince(started)), privacy: .public)s")
		return footprints
	}

	/// A building drawn in parts is drawn by its parts alone. Its outline covers the whole
	/// footprint at the full height, so drawn as well it hides them: the Space Needle comes out as
	/// one tall column. An outline with a point of a part inside it (and not in one of its
	/// courtyards) is left out. Nil when cancelled.
	static func withoutOutlinesOfParts(_ footprints: [SpatialBuildingFootprint]) -> [SpatialBuildingFootprint]? {
		let points = footprints.filter(\.isPart).compactMap { interiorPoint($0.outline) }
		guard !points.isEmpty else { return footprints }
		var kept: [SpatialBuildingFootprint] = []
		kept.reserveCapacity(footprints.count)
		for footprint in footprints {
			if Task.isCancelled { return nil }
			let coversPart = !footprint.isPart && points.contains { point in
				contains(footprint.outline, point) && !footprint.holes.contains { contains($0, point) }
			}
			if !coversPart { kept.append(footprint) }
		}
		return kept
	}

	/// A point inside the outline even when it's concave, where the average of the corners can
	/// fall outside (a U-shaped part): the middle of the largest triangle filling it. Worked in
	/// meters-ish offsets from the first corner so Float keeps sub-meter precision.
	static func interiorPoint(_ outline: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
		guard let origin = outline.first else { return nil }
		var points = Self.outline(outline.map { c in
			SIMD2(Float((c.longitude - origin.longitude) * 1e5), Float((c.latitude - origin.latitude) * 1e5))
		})
		guard points.count >= 3 else { return nil }
		if signedArea(points) < 0 { points.reverse() }
		let roof = triangulate(points)
		var best: (area: Float, middle: SIMD2<Float>)?
		for t in stride(from: 0, to: roof.count, by: 3) {
			let a = points[Int(roof[t])], b = points[Int(roof[t + 1])], c = points[Int(roof[t + 2])]
			let area = abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
			if area > best?.area ?? 0 { best = (area, (a + b + c) / 3) }
		}
		guard let middle = best?.middle else { return nil }
		return CLLocationCoordinate2D(latitude: origin.latitude + Double(middle.y) / 1e5, longitude: origin.longitude + Double(middle.x) / 1e5)
	}

	/// Whether the point is inside the outline, by counting the edges a line east from it crosses.
	static func contains(_ outline: [CLLocationCoordinate2D], _ point: CLLocationCoordinate2D) -> Bool {
		var inside = false
		var j = outline.count - 1
		for i in outline.indices {
			let a = outline[i], b = outline[j]
			if (a.latitude > point.latitude) != (b.latitude > point.latitude),
			   point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
				inside.toggle()
			}
			j = i
		}
		return inside
	}

	// MARK: Mesh

	/// The buildings on the disk as one flat-shaded mesh in model units: walls and a flat roof each,
	/// standing on the lowest ground under the outline and raised to their real heights. The terrain
	/// is stretched upward so hills read; a building stretched with it turns a slim tower like the
	/// Space Needle into a pole.
	/// A building with any corner past the disk's edge is left out, and the largest are kept first
	/// when there are more triangles than `triangleBudget`.
	static func mesh(_ footprints: [SpatialBuildingFootprint], geometry: SpatialTerrainGeometry, triangleBudget: Int = triangleBudget) -> SpatialMeshData {
		let transform = geometry.transform
		let heightScale = Float(transform.scale)
		let limit = transform.diskRadius * diskShare
		struct Placed {
			let outline: [SIMD2<Float>]
			let ground: Float
			let bottom: Float
			let top: Float
			let area: Float
		}
		var placed: [Placed] = []
		placed.reserveCapacity(footprints.count)
		for footprint in footprints {
			var outline = Self.outline(footprint.outline.map { coordinate -> SIMD2<Float> in
				let p = transform.position(coordinate, altitude: transform.baseElevation)
				return SIMD2(p.x, p.z)
			})
			guard outline.count >= 3 else { continue }
			let area = signedArea(outline)
			guard abs(area) > 0 else { continue }
			// Corners in order of increasing angle (x toward z), the order the faces below expect.
			if area < 0 { outline.reverse() }
			guard outline.allSatisfy({ simd_length($0) <= limit }) else { continue }
			let ground = footprint.outline.map { geometry.groundHeight(at: $0) }.min() ?? 0
			let height = max(footprint.height ?? defaultHeight, 1)
			let minHeight = min(max(footprint.minHeight, 0), height - 1)
			placed.append(Placed(outline: outline, ground: ground, bottom: ground + Float(minHeight) * heightScale, top: ground + Float(height) * heightScale, area: abs(area)))
		}
		placed.sort { $0.area > $1.area }

		var mesh = SpatialMeshData()
		var triangles = 0
		for building in placed {
			let roof = triangulate(building.outline)
			let cost = 2 * building.outline.count + roof.count / 3
			guard triangles + cost <= triangleBudget else { break }
			triangles += cost
			mesh.addBuilding(outline: building.outline, roof: roof, bottom: building.bottom, top: building.top)
		}
		return mesh
	}

	/// Drops repeated corners, including a last corner that closes the ring onto the first.
	static func outline(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
		var result: [SIMD2<Float>] = []
		for p in points where result.last.map({ simd_distance($0, p) > 1e-7 }) ?? true {
			result.append(p)
		}
		while result.count > 1, let first = result.first, let last = result.last, simd_distance(first, last) <= 1e-7 {
			result.removeLast()
		}
		return result
	}

	/// Twice the area, positive when the corners run in order of increasing angle (x toward z).
	static func signedArea(_ outline: [SIMD2<Float>]) -> Float {
		var sum: Float = 0
		for i in outline.indices {
			let p = outline[i], q = outline[(i + 1) % outline.count]
			sum += p.x * q.y - q.x * p.y
		}
		return sum
	}

	/// Triangles filling an outline whose corners run in order of increasing angle, by cutting off
	/// one corner at a time, so L-shaped and other concave roofs fill correctly. Each triangle is
	/// in the outline's own order. A tangled outline that can't be cut falls back to a fan.
	static func triangulate(_ outline: [SIMD2<Float>]) -> [UInt32] {
		let count = outline.count
		guard count >= 3 else { return [] }
		var remaining = Array(0..<count)
		var result: [UInt32] = []
		result.reserveCapacity((count - 2) * 3)
		func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
			(b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
		}
		func inside(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
			cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0
		}
		var guardCount = 0
		while remaining.count > 3 && guardCount < count * count {
			guardCount += 1
			var cut = false
			for k in remaining.indices {
				let ia = remaining[(k + remaining.count - 1) % remaining.count]
				let ib = remaining[k]
				let ic = remaining[(k + 1) % remaining.count]
				let a = outline[ia], b = outline[ib], c = outline[ic]
				guard cross(a, b, c) > 0 else { continue }
				let blocked = remaining.contains { j in
					j != ia && j != ib && j != ic && inside(outline[j], a, b, c)
				}
				guard !blocked else { continue }
				result += [UInt32(ia), UInt32(ib), UInt32(ic)]
				remaining.remove(at: k)
				cut = true
				break
			}
			if !cut { break }
		}
		if remaining.count == 3 {
			result += remaining.map(UInt32.init)
		} else if remaining.count > 3 {
			for k in 1..<(remaining.count - 1) {
				result += [UInt32(remaining[0]), UInt32(remaining[k]), UInt32(remaining[k + 1])]
			}
		}
		return result
	}
}

extension SpatialMeshData {
	/// A building: walls from `bottom` to `top` around `outline` (x and z, corners in order of
	/// increasing angle) and a flat roof filled by `roof`, triangles of outline indices. No floor:
	/// it stands on the ground.
	mutating func addBuilding(outline: [SIMD2<Float>], roof: [UInt32], bottom: Float, top: Float) {
		let first = UInt32(positions.count)
		positions += outline.map { SIMD3($0.x, top, $0.y) }
		normals += Array(repeating: SIMD3(0, 1, 0), count: outline.count)
		// Seen from above the outline runs the other way round, so each triangle is turned over.
		for t in stride(from: 0, to: roof.count, by: 3) {
			indices += [first + roof[t], first + roof[t + 2], first + roof[t + 1]]
		}
		for i in outline.indices {
			let p = outline[i], q = outline[(i + 1) % outline.count]
			let edge = q - p
			let normal = simd_normalize(SIMD3(edge.y, 0, -edge.x))
			let wall = UInt32(positions.count)
			positions += [SIMD3(q.x, bottom, q.y), SIMD3(p.x, bottom, p.y), SIMD3(p.x, top, p.y), SIMD3(q.x, top, q.y)]
			normals += Array(repeating: normal, count: 4)
			indices += [wall, wall + 1, wall + 2, wall, wall + 2, wall + 3]
		}
	}
}
