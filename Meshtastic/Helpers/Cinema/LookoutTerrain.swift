//
//  LookoutTerrain.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
/// How prominent a summit has to be to make the fire lookout's list. Outside the visionOS-only
/// code so it can be tested.
enum LookoutSummitBar {
	/// Prominence bars in meters, strictest first: real mountains, then hills, then bumps.
	static let steps: [Float] = [300, 150, 50, 0]
	/// Enough summits to choose from; the bar is lowered until this many clear it.
	static let enough = 10

	/// The strictest bar at least `enough` of these prominences clear, or the lowest bar.
	static func bar(for prominences: [Float]) -> Float {
		steps.first { least in prominences.filter { $0 >= least }.count >= enough } ?? steps[steps.count - 1]
	}
}

#if os(visionOS)
import CoreGraphics
import CoreLocation
import Foundation
import OSLog
import RealityKit
import simd

/// A place a cinema environment can stand: a summit, one of the highest points in the terrain the
/// app has downloaded for the spatial map, a headland the lighthouse can stand on at the water's
/// edge, or the roof of one of the tallest buildings in it.
struct LookoutSite: Identifiable, Hashable, Codable, Sendable {
	let latitude: Double
	let longitude: Double
	/// The ground's height above sea level, in meters.
	let elevation: Float
	/// The peak's name from the downloaded basemap, if it has one.
	let name: String?
	/// On a rooftop or a sky deck, how tall the building is; nil elsewhere.
	var rooftop: Float?
	/// For a headland, the true bearing of the open water it looks out on; for a sky deck, the
	/// bearing it hangs out from its tower along; nil elsewhere.
	var facing: Double?

	/// Whether it's a sky deck: a building's height, and a bearing out from its face.
	var isSkyDeck: Bool {
		rooftop != nil && facing != nil
	}

	/// How far above the ground the floor the viewer sits on is: the lookout's tower on a summit, the
	/// lighthouse's on a headland, the building on a rooftop.
	var standHeight: Double {
		if let rooftop { return Double(rooftop) }
		return (facing == nil ? LookoutSiteKind.summit : .coast).standHeight
	}

	/// Its place to four decimals on a summit, and to five (about a meter) on a rooftop, so the map
	/// can find the roof from it.
	var id: String {
		String(format: rooftop == nil ? "%.4f,%.4f" : "%.5f,%.5f", latitude, longitude)
	}

	var coordinate: CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}
}

/// The terrain around a lookout site as a mesh and its shading, built off the main actor.
struct LookoutTerrainModel: Sendable {
	let site: LookoutSite
	let positions: [SIMD3<Float>]
	let textureCoordinates: [SIMD2<Float>]
	let indices: [UInt32]
	let texture: CGImage
	/// The conifers on the forested ground near the summit; nil where none is forest.
	let trees: LookoutForestMesh?
}

/// The near forest as one mesh, colored from a small palette with the sun's light painted in.
struct LookoutForestMesh: Sendable {
	/// A textured mesh: the near trees with their palette, or the rows with their painted trees.
	struct Part: Sendable {
		let positions: [SIMD3<Float>]
		let textureCoordinates: [SIMD2<Float>]
		let indices: [UInt32]
		let texture: CGImage
	}

	let trees: Part?
	let rows: Part?
}

/// Real terrain seen from the lookout's cab. The ground is sampled from the downloaded elevation
/// tiles in rings around the site and placed by its true bearing and angle above the horizon from a
/// seated eye on the summit, so every ridge is where it really is. The rings are then pushed out
/// along those lines of sight to between the room sphere and the sky, so the painted cab hides the
/// ground except through its glass, and the sky sphere stays behind everything.
enum LookoutTerrain {
	/// Rings of samples from the cab out to the edge of the downloaded area.
	static let rings = 96
	/// Samples around each ring: one every half degree.
	static let spokes = 720
	static let innerRadius = 20.0
	static let maxRadius = 90_000.0
	/// The true bearing the cab's front (the screen) faces, so the painted sunset sits in the
	/// west-northwest where a sunset is.
	static let frontHeading = SpatialLookout.frontHeading
	/// Earth's radius with the usual allowance for refraction: far ridges sit below a flat horizon.
	static let earthRadius = LookoutForest.earthRadius
	/// The cab's floor stands this far above the summit, on a tower a little taller than most real
	/// ones (under 30 m), so the view looks down onto the ground around the summit.
	static let cabHeight = LookoutSiteKind.summit.standHeight
	/// The seated eye above the cab's floor.
	static let eyeHeight = 1.15

	/// The eye's elevation in a room whose floor is `standHeight` above `site`, or the site's own
	/// stand height when nil.
	static func eyeElevation(for site: LookoutSite, standHeight: Double? = nil) -> Double {
		Double(site.elevation) + (standHeight ?? site.standHeight) + eyeHeight
	}
	/// How far out a point `distance` meters away is drawn: from just past the room sphere to just
	/// short of the sky, keeping the order of what's near and far.
	static func depth(_ distance: Double) -> Float {
		Float(55 + 845 * (1 - exp(-distance / 15_000)))
	}

	/// The unit direction, in the cinema's frame, of a point at a true `bearing` and horizontal
	/// `distance` from the eye, `rise` meters above it before the Earth's curve is taken off.
	static func direction(bearing: Double, distance: Double, rise: Double, heading: Double = frontHeading) -> SIMD3<Float> {
		let azimuth = (bearing - heading) * .pi / 180
		let drop = distance * distance / (2 * earthRadius)
		let flat = SIMD3<Float>(Float(sin(azimuth) * distance), Float(rise - drop), Float(-cos(azimuth) * distance))
		return simd_normalize(flat)
	}

	// MARK: Sites

	/// The mountains in `bounds`: the highest peaks that stand well clear of the ground around them,
	/// at least 3 km apart, highest first, at most `count` of them, all inside `area` when one is
	/// given. Picking by height alone would fill the list with the shoulders of the one or two
	/// tallest mountains. Empty when the task is cancelled.
	static func sites(in bounds: GeoBounds, source: any ElevationTileSource, area: SpatialCircle? = nil, count: Int = 20) async -> [LookoutSite] {
		let frame = SpatialFrame(bounds: bounds)
		// About 250 m cells, up to 600 across; a whole state gets cells near 800 m.
		let columns = min(600, max(48, Int(frame.widthMeters / 250)))
		let rows = min(600, max(48, Int(frame.depthMeters / 250)))
		guard let grid = await highestGrid(in: bounds, columns: columns, rows: rows, zoom: 10, source: source) else {
			return []
		}
		let peaks = prominentPeaks(in: grid)
		// Real mountains have 300 m of prominence. Where only a few do, hills with less join them,
		// so a lowland mesh still has summits to choose from.
		let least = LookoutSummitBar.bar(for: peaks.map(\.prominence))
		let chosen = peaks.filter { $0.prominence >= least }
		// The coarse grid only says which cell the summit is in, give or take one; the finest
		// tiles say where in it.
		let cell = max(frame.widthMeters / Double(grid.columns), frame.depthMeters / Double(grid.rows))
		let zoom = min(14, await source.finestDataZoom() ?? 12)
		let sampler = Sampler(source: source)
		var coarse: [CLLocationCoordinate2D] = []
		var distinct: [LookoutSite] = []
		// Refined one at a time until there are `count` inside the area, so summits outside it
		// don't take places in the list.
		for peak in chosen where distinct.count < count {
			if Task.isCancelled { return [] }
			let column = peak.index % grid.columns
			let row = peak.index / grid.columns
			let latitude = bounds.maxLat - (bounds.maxLat - bounds.minLat) * (Double(row) + 0.5) / Double(grid.rows)
			let longitude = bounds.minLon + (bounds.maxLon - bounds.minLon) * (Double(column) + 0.5) / Double(grid.columns)
			let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
			if coarse.contains(where: { $0.distance(from: coordinate) < 3_000 }) { continue }
			coarse.append(coordinate)
			// Refining moves a summit by a cell and a half at most, so one further out can't reach the area.
			if let area, area.distanceMeters(to: coordinate) > area.radiusMeters + cell * 1.5 { continue }
			let site = await refine(LookoutSite(latitude: latitude, longitude: longitude, elevation: peak.elevation, name: nil), within: cell, zoom: zoom, sampler: sampler)
			guard area?.contains(site.coordinate) ?? true else { continue }
			// Two coarse summits can climb to the same top when the cells are wide; keep the higher.
			if let near = distinct.firstIndex(where: { $0.coordinate.distance(from: site.coordinate) < 3_000 }) {
				if site.elevation > distinct[near].elevation { distinct[near] = site }
				continue
			}
			distinct.append(site)
		}
		if Task.isCancelled { return [] }
		return distinct.sorted { $0.elevation > $1.elevation }
	}

	/// The headlands in `bounds` a lighthouse could stand on: land at the water's edge looking out
	/// over the most open sea, at least 3 km apart, best first, at most `count` of them, all inside
	/// `area` when one is given, each facing the middle of its open water. Empty with no coast, or
	/// when the task is cancelled.
	static func coastSites(in bounds: GeoBounds, source: any ElevationTileSource, area: SpatialCircle? = nil, count: Int = 20) async -> [LookoutSite] {
		let frame = SpatialFrame(bounds: bounds)
		let columns = min(600, max(48, Int(frame.widthMeters / 250)))
		let rows = min(600, max(48, Int(frame.depthMeters / 250)))
		guard let grid = await highestGrid(in: bounds, columns: columns, rows: rows, zoom: 10, source: source) else {
			return []
		}
		let cellWidth = frame.widthMeters / Double(columns)
		let cellHeight = frame.depthMeters / Double(rows)
		let candidates = LookoutCoast.candidates(in: LookoutCoast.Grid(heights: grid.heights, covered: grid.covered, columns: columns, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight))
		if Task.isCancelled { return [] }
		let zoom = min(14, await source.finestDataZoom() ?? 12)
		let sampler = Sampler(source: source)
		var chosen: [LookoutSite] = []
		for candidate in candidates where chosen.count < count {
			if Task.isCancelled { return [] }
			let column = candidate.index % columns
			let row = candidate.index / columns
			let latitude = bounds.maxLat - (bounds.maxLat - bounds.minLat) * (Double(row) + 0.5) / Double(rows)
			let longitude = bounds.minLon + (bounds.maxLon - bounds.minLon) * (Double(column) + 0.5) / Double(columns)
			let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
			guard area?.contains(coordinate) ?? true, !chosen.contains(where: { $0.coordinate.distance(from: coordinate) < 3_000 }) else { continue }
			// The top of the headland within its cell, so the tower stands on the cliff top rather
			// than the cell's middle, which may be over the water.
			let coarse = LookoutSite(latitude: latitude, longitude: longitude, elevation: candidate.elevation, name: nil, facing: candidate.facing)
			let site = await refine(coarse, within: max(cellWidth, cellHeight) / 2, zoom: zoom, sampler: sampler, steps: [(max(cellWidth, cellHeight) / 2, 25), (30, 5)])
			guard site.elevation > 0 else { continue }
			chosen.append(site)
		}
		return chosen
	}

	/// The highest ground in each cell of a coarse grid over the downloaded area, row-major from the
	/// north-west corner.
	private struct HighGrid {
		let columns: Int
		let rows: Int
		let heights: [Float]
		let covered: [Bool]
	}

	/// The highest ground in each cell of a `columns` by `rows` grid over `bounds`, read from every
	/// pixel of the tiles at `zoom`, so a narrow summit counts for its cell at its full height. A
	/// top pixel standing alone far above the next in its cell is taken at the next: the data has
	/// isolated spikes over water.
	private static func highestGrid(in bounds: GeoBounds, columns: Int, rows: Int, zoom: Int, source: any ElevationTileSource) async -> HighGrid? {
		let count = columns * rows
		var highest = [Float](repeating: -.greatestFiniteMagnitude, count: count)
		var second = [Float](repeating: -.greatestFiniteMagnitude, count: count)
		var covered = [Bool](repeating: false, count: count)
		let size = TerrainStore.tileSize
		let topLeft = TerrainStore.tilePixel(latitude: bounds.maxLat, longitude: bounds.minLon, z: zoom, size: size)
		let bottomRight = TerrainStore.tilePixel(latitude: bounds.minLat, longitude: bounds.maxLon, z: zoom, size: size)
		let tiles = Double(1 << zoom)
		let latitudeSpan = bounds.maxLat - bounds.minLat
		let longitudeSpan = bounds.maxLon - bounds.minLon
		for tileY in topLeft.y...bottomRight.y {
			for tileX in topLeft.x...bottomRight.x {
				guard !Task.isCancelled else { return nil }
				guard let coverage = await source.coverage(z: zoom, x: tileX, y: tileY),
					  let tile = await source.elevationTile(z: zoom, x: tileX, y: tileY, margin: 0) else { continue }
				let minLat = max(bounds.minLat, coverage.minLat)
				let maxLat = min(bounds.maxLat, coverage.maxLat)
				let minLon = max(bounds.minLon, coverage.minLon)
				let maxLon = min(bounds.maxLon, coverage.maxLon)
				// Which cell each pixel column and row of this tile falls in, -1 for outside.
				let cellColumns: [Int] = (0..<tile.size).map { px in
					let longitude = (Double(tileX) + (Double(px) + 0.5) / Double(tile.size)) / tiles * 360 - 180
					guard longitude >= minLon, longitude <= maxLon else { return -1 }
					return min(columns - 1, Int((longitude - bounds.minLon) / longitudeSpan * Double(columns)))
				}
				let cellRows: [Int] = (0..<tile.size).map { py in
					let latitude = atan(sinh(.pi * (1 - 2 * (Double(tileY) + (Double(py) + 0.5) / Double(tile.size)) / tiles))) * 180 / .pi
					guard latitude >= minLat, latitude <= maxLat else { return -1 }
					return min(rows - 1, Int((bounds.maxLat - latitude) / latitudeSpan * Double(rows)))
				}
				for py in 0..<tile.size {
					let row = cellRows[py]
					guard row >= 0 else { continue }
					let rowStart = (py + tile.margin) * tile.gridSize + tile.margin
					for px in 0..<tile.size {
						let column = cellColumns[px]
						guard column >= 0 else { continue }
						let index = row * columns + column
						let elevation = tile.elevations[rowStart + px]
						covered[index] = true
						if elevation > highest[index] {
							second[index] = highest[index]
							highest[index] = elevation
						} else if elevation > second[index] {
							second[index] = elevation
						}
					}
				}
			}
		}
		guard covered.contains(true) else { return nil }
		var heights = [Float](repeating: 0, count: count)
		for index in 0..<count where covered[index] {
			let top = highest[index]
			let next = second[index] > -.greatestFiniteMagnitude ? second[index] : top
			heights[index] = max(0, top - next > 200 ? next : top)
		}
		return HighGrid(columns: columns, rows: rows, heights: heights, covered: covered)
	}

	/// A local top in the coarse grid and how far it rises above the saddle joining it to higher ground.
	private struct Peak {
		let index: Int
		let elevation: Float
		let prominence: Float
	}

	/// Every local top in `grid` with its prominence, highest first. The water is lowered over the
	/// grid a cell at a time; each top is an island until it joins a taller one, and the height the
	/// two join at is the saddle between them.
	private static func prominentPeaks(in grid: HighGrid) -> [Peak] {
		let count = grid.heights.count
		let order = (0..<count).filter { grid.covered[$0] }.sorted { grid.heights[$0] > grid.heights[$1] }
		// Union-find over the cells above water: -1 is still under water.
		var parent = [Int](repeating: -1, count: count)
		// The top of each island, by its root.
		var top = [Int](repeating: 0, count: count)
		var prominence = [Float](repeating: 0, count: count)
		var tops: [Int] = []

		func root(of cell: Int) -> Int {
			var found = cell
			while parent[found] != found { found = parent[found] }
			var walk = cell
			while parent[walk] != found {
				let next = parent[walk]
				parent[walk] = found
				walk = next
			}
			return found
		}

		for cell in order {
			parent[cell] = cell
			top[cell] = cell
			let column = cell % grid.columns
			let row = cell / grid.columns
			var joined = false
			for rowStep in -1...1 {
				for columnStep in -1...1 where rowStep != 0 || columnStep != 0 {
					let neighborRow = row + rowStep
					let neighborColumn = column + columnStep
					guard neighborRow >= 0, neighborRow < grid.rows, neighborColumn >= 0, neighborColumn < grid.columns else { continue }
					let neighbor = neighborRow * grid.columns + neighborColumn
					guard parent[neighbor] != -1 else { continue }
					joined = true
					let mine = root(of: cell)
					let theirs = root(of: neighbor)
					guard mine != theirs else { continue }
					// The lower island drowns into the taller one here, at this cell's height; on a
					// tie the island that was there first keeps its top.
					let (taller, lower) = grid.heights[top[mine]] > grid.heights[top[theirs]] ? (mine, theirs) : (theirs, mine)
					prominence[top[lower]] = grid.heights[top[lower]] - grid.heights[cell]
					parent[lower] = taller
				}
			}
			if !joined { tops.append(cell) }
		}
		return tops.map { cell in
			// A top that never joined a taller island is the highest ground there is.
			let rise = root(of: cell) == cell && top[cell] == cell ? grid.heights[cell] : prominence[cell]
			return Peak(index: cell, elevation: grid.heights[cell], prominence: rise)
		}
		.sorted { $0.elevation > $1.elevation }
	}

	/// The highest point near `site` in the tiles at `zoom`: a first pass 100 m apart out to a cell
	/// and a half away, since the coarse grid can put a summit a cell off, then 20 m and 5 m apart
	/// around the best so far. The fine tiles decide the height, not the coarse grid.
	private static func refine(_ site: LookoutSite, within cell: Double, zoom: Int, sampler: Sampler, steps: [(reach: Double, step: Double)]? = nil) async -> LookoutSite {
		var best: LookoutSite?
		for (reach, step) in steps ?? [(cell * 1.5, 100.0), (120, 20), (25, 5)] {
			let center = best ?? site
			let metersPerDegreeLatitude = SpatialFrame.metersPerDegreeLatitude
			let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(center.latitude * .pi / 180)
			for north in stride(from: -reach, through: reach, by: step) {
				for east in stride(from: -reach, through: reach, by: step) {
					let latitude = center.latitude + north / metersPerDegreeLatitude
					let longitude = center.longitude + east / metersPerDegreeLongitude
					if let elevation = await sampler.elevation(latitude: latitude, longitude: longitude, zoom: zoom), elevation > (best?.elevation ?? -.greatestFiniteMagnitude) {
						best = LookoutSite(latitude: latitude, longitude: longitude, elevation: elevation, name: site.name, facing: site.facing)
					}
				}
			}
		}
		return best ?? site
	}

	// MARK: The mesh

	/// How far the terrain reaches from `site`: to the farthest corner of the downloaded box, at
	/// most `maxRadius`.
	static func outerRadius(site: LookoutSite, bounds: GeoBounds) -> Double {
		let corners = [(bounds.minLat, bounds.minLon), (bounds.minLat, bounds.maxLon), (bounds.maxLat, bounds.minLon), (bounds.maxLat, bounds.maxLon)]
		let reach = corners.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1).distance(from: site.coordinate) }.max() ?? maxRadius
		return min(maxRadius, max(5_000, reach))
	}

	/// Builds the terrain around `site`, out to `bounds` and at most `maxRadius`, seen from a room
	/// whose floor is `standHeight` above it. `sun` is where the painted sky's sun is, degrees
	/// clockwise from the cab's front and above the horizon. The ground is colored from `landCover`
	/// where it has the point, else by height. `progress` hears each ring read, then the drawing.
	static func build(
		site: LookoutSite, bounds: GeoBounds, source: any ElevationTileSource, landCover: OfflineLandCoverMap? = nil,
		heading: Double = frontHeading, standHeight: Double? = nil, sun: (azimuth: Float, elevation: Float),
		progress: @escaping @Sendable (SpatialTerrainProgress) -> Void = { _ in }
	) async -> LookoutTerrainModel? {
		let sampler = Sampler(source: source)
		let floor = Double(site.elevation) + (standHeight ?? site.standHeight)
		let eye = floor + eyeHeight
		let metersPerDegreeLatitude = SpatialFrame.metersPerDegreeLatitude
		let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(site.latitude * .pi / 180)
		let outerRadius = outerRadius(site: site, bounds: bounds)

		let columns = spokes + 1
		var elevations = [Float](repeating: 0, count: rings * columns)
		var known = [Bool](repeating: false, count: rings * columns)
		var covers = [OfflineLandCover?](repeating: nil, count: rings * columns)
		var distances = [Double](repeating: 0, count: rings)
		var lowest = Float.greatestFiniteMagnitude
		// A sky deck's glass floor shows the ground straight down, so its rings start right under it.
		let inner = site.isSkyDeck ? 1.5 : innerRadius
		for ring in 0..<rings {
			let distance = inner * pow(outerRadius / inner, Double(ring) / Double(rings - 1))
			distances[ring] = distance
			let zoom = distance < 1_500 ? 14 : distance < 6_000 ? 12 : distance < 25_000 ? 11 : 10
			for spoke in 0..<columns {
				let bearing = Double(spoke % spokes) / Double(spokes) * 2 * .pi
				let latitude = site.latitude + distance * cos(bearing) / metersPerDegreeLatitude
				let longitude = site.longitude + distance * sin(bearing) / metersPerDegreeLongitude
				covers[ring * columns + spoke] = landCover?.cover(latitude: latitude, longitude: longitude)
				if var elevation = await sampler.elevation(latitude: latitude, longitude: longitude, zoom: zoom) {
					// The tower's footing cuts the summit flat: nothing right around it stands above
					// its floor.
					if distance < 40 {
						elevation = min(elevation, Float(floor - 0.5))
					}
					let index = ring * columns + spoke
					elevations[index] = max(0, elevation)
					known[index] = true
					lowest = min(lowest, elevations[index])
				}
			}
			if Task.isCancelled { return nil }
			progress(SpatialTerrainProgress(phase: .elevation(done: ring + 1, total: rings)))
		}
		progress(SpatialTerrainProgress(phase: .drawing))
		guard lowest < .greatestFiniteMagnitude else { return nil }
		// Ground with no data takes the lowest level there is, which the haze mostly hides.
		for index in 0..<elevations.count where !known[index] {
			elevations[index] = lowest
		}
		let highest = elevations.max() ?? lowest

		var positions = [SIMD3<Float>](repeating: .zero, count: rings * columns)
		var uvs = [SIMD2<Float>](repeating: .zero, count: rings * columns)
		// True local positions, east/up/north, for the shading.
		var local = [SIMD3<Double>](repeating: .zero, count: rings * columns)
		for ring in 0..<rings {
			let distance = distances[ring]
			for spoke in 0..<columns {
				let index = ring * columns + spoke
				let bearing = Double(spoke % spokes) / Double(spokes) * 360
				let radians = bearing * .pi / 180
				let elevation = Double(elevations[index])
				local[index] = SIMD3(sin(radians) * distance, elevation, cos(radians) * distance)
				positions[index] = direction(bearing: bearing, distance: distance, rise: elevation - eye, heading: heading) * depth(distance)
				uvs[index] = SIMD2(Float(spoke) / Float(spokes), Float(ring) / Float(rings - 1))
			}
		}

		var indices: [UInt32] = []
		indices.reserveCapacity((rings - 1) * spokes * 6)
		for ring in 0..<(rings - 1) {
			for spoke in 0..<spokes {
				let a = UInt32(ring * columns + spoke)
				let b = a + 1
				let c = UInt32((ring + 1) * columns + spoke + 1)
				let d = c - 1
				indices += [a, b, c, a, c, d]
			}
		}

		let ground = Ground(elevations: elevations, covers: covers, distances: distances, lowest: lowest, highest: highest, latitude: site.latitude, heading: heading)
		guard let texture = shade(local: local, ground: ground, distances: distances, sun: sun) else { return nil }
		let trees = forest(site: site, eye: eye, ground: ground, landCover: landCover, sun: sun)
		if Task.isCancelled { return nil }
		return LookoutTerrainModel(site: site, positions: positions, textureCoordinates: uvs, indices: indices, texture: texture, trees: trees)
	}

	/// The forest on the forested ground that shows over the cab's sill, out to 15 km (see
	/// `LookoutForest`): true-size cones near the summit, rows of painted trees beyond. Each stands
	/// on the terrain as it's drawn, and every corner is placed along its own line of sight like
	/// the terrain's, so the forest sits in front of or behind the ground where it should. Nothing
	/// hidden behind nearer ground is drawn. Nil when no forest shows, or the task is cancelled.
	private static func forest(
		site: LookoutSite, eye: Double, ground: Ground, landCover: OfflineLandCoverMap?, sun: (azimuth: Float, elevation: Float)
	) -> LookoutForestMesh? {
		let distances = ground.distances
		let metersPerDegreeLatitude = SpatialFrame.metersPerDegreeLatitude
		let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(site.latitude * .pi / 180)
		let sunBearing = Double(sun.azimuth) + ground.heading
		let sunAzimuth = sunBearing * .pi / 180
		let sunElevation = Double(sun.elevation) * .pi / 180
		let light = SIMD3<Double>(sin(sunAzimuth) * cos(sunElevation), sin(sunElevation), cos(sunAzimuth) * cos(sunElevation))
		let range = Double(max(1, ground.highest - ground.lowest))
		let horizon = LookoutForest.horizon(distances: distances, elevations: ground.elevations, spokes: spokes, eye: eye)
		let columns = spokes + 1
		let reach = min(LookoutForest.reach, distances.last ?? 0)
		func forested(bearing: Double, distance: Double, elevation: Double) -> Bool {
			let radians = bearing * .pi / 180
			let cover = landCover?.cover(
				latitude: site.latitude + cos(radians) * distance / metersPerDegreeLatitude,
				longitude: site.longitude + sin(radians) * distance / metersPerDegreeLongitude
			)
			return LookoutForest.isForest(cover: cover, elevation: elevation, latitude: site.latitude, heightFraction: (elevation - Double(ground.lowest)) / range)
		}
		func surface(_ bearing: Double, _ distance: Double) -> Double? {
			LookoutForest.groundElevation(bearing: bearing, distance: distance, distances: distances, elevations: ground.elevations, spokes: spokes).map(Double.init)
		}
		func shows(top: Double, bearing: Double, distance: Double) -> Bool {
			let spoke = min(spokes - 1, Int(bearing / 360 * Double(spokes)))
			// The horizon past the ring just inside the point: it counts that ring too, which is nearer.
			let past = min(LookoutForest.ring(inside: distance, distances: distances) + 1, distances.count - 1)
			return LookoutForest.shows(top: top, distance: distance, eye: eye, horizon: horizon[past * columns + spoke])
		}
		func place(_ point: SIMD3<Double>) -> SIMD3<Float> {
			let distance = max(1, hypot(point.x, point.z))
			var bearing = atan2(point.x, point.z) * 180 / .pi
			if bearing < 0 { bearing += 360 }
			return direction(bearing: bearing, distance: distance, rise: point.y - eye, heading: ground.heading) * depth(distance)
		}
		var triangles = 0
		var cancelled = false

		// Near trees: the painting's cones, true size, packed like its forest.
		var treePositions: [SIMD3<Float>] = []
		var treeUVs: [SIMD2<Float>] = []
		var trees = 0
		let tallest = LookoutForest.nearCones.map(\.tip).max() ?? 12.5
		var looked = 0
		/// Plants a tree if it stands on forest, shows, and fits in `budget`. One that doesn't fit is
		/// skipped rather than ending the planting: a farther, simpler tree may still fit.
		func plant(_ spot: LookoutForest.Spot, near: Bool, budget: Int = LookoutForest.triangleBudget) {
			let cost = near ? LookoutForest.nearCones.count * LookoutForest.nearSides : LookoutForest.farCones.count * LookoutForest.farSides
			guard triangles + cost <= budget else { return }
			guard let height = surface(spot.bearing, spot.distance),
				  shows(top: height + tallest * spot.height, bearing: spot.bearing, distance: spot.distance),
				  forested(bearing: spot.bearing, distance: spot.distance, elevation: height) else { return }
			let radians = spot.bearing * .pi / 180
			// Sunk a little, so no tree shows a gap under it on a slope.
			let base = SIMD3<Double>(sin(radians) * spot.distance, height - 0.5 * spot.height, cos(radians) * spot.distance)
			for face in LookoutForest.faces(turn: spot.turn, width: spot.width, height: spot.height, near: near) {
				let uv = LookoutForest.paletteCoordinate(shade: spot.shade, lit: max(0, simd_dot(face.normal, light)), distance: spot.distance)
				for corner in face.corners {
					treePositions.append(place(base + corner))
					treeUVs.append(uv)
				}
			}
			triangles += cost
			trees += 1
		}
		LookoutForest.forEachSpot(farthest: min(LookoutForest.rowsFrom, reach)) { spot in
			looked += 1
			if looked.isMultiple(of: 4_096), Task.isCancelled {
				cancelled = true
				return false
			}
			plant(spot, near: spot.distance < LookoutForest.nearDetail)
			return true
		}
		if cancelled { return nil }

		// The front band: big trees where the forest first shows in each direction past the near
		// trees. Where near trees show, they're the front already.
		let nearTriangles = triangles
		for spoke in 0..<spokes {
			if Task.isCancelled { return nil }
			let bearing = (Double(spoke) + 0.5) * 360 / Double(spokes)
			var front: Double?
			for (ring, distance) in distances.enumerated() where distance >= LookoutForest.nearest && distance <= reach {
				let elevation = Double(ground.elevations[ring * columns + spoke])
				if shows(top: elevation + tallest, bearing: bearing, distance: distance),
				   forested(bearing: bearing, distance: distance, elevation: elevation) {
					front = distance
					break
				}
			}
			guard let front, front >= LookoutForest.rowsFrom else { continue }
			let budget = min(LookoutForest.triangleBudget, nearTriangles + LookoutForest.frontBudget)
			LookoutForest.forEachFrontSpot(spoke: spoke, spokes: spokes, from: front) { plant($0, near: true, budget: budget); return true }
		}

		// Rows of painted trees beyond, one strip per spoke at each step out.
		var rowPositions: [SIMD3<Float>] = []
		var rowUVs: [SIMD2<Float>] = []
		var rowIndices: [UInt32] = []
		var rows = 0
		let spokeWidth = 360 / Double(spokes)
		looked = 0
		LookoutForest.forEachRow(farthest: reach, spokes: spokes) { row in
			looked += 1
			if looked.isMultiple(of: 8_192), Task.isCancelled {
				cancelled = true
				return false
			}
			guard triangles + 2 <= LookoutForest.triangleBudget else { return false }
			guard row.chance < LookoutForest.density(at: row.distance) else { return true }
			let left = Double(row.spoke) * spokeWidth
			let right = left + spokeWidth
			let middle = left + spokeWidth / 2
			let tall = LookoutForest.rowHeight * LookoutForest.rowScale(at: row.distance)
			// Forest across the whole strip, so none stands out over a field or a town.
			guard let low = surface(left, row.distance), let high = surface(right, row.distance), let center = surface(middle, row.distance),
				  shows(top: center + tall * 0.6, bearing: middle, distance: row.distance),
				  forested(bearing: middle, distance: row.distance, elevation: center),
				  forested(bearing: left, distance: row.distance, elevation: low),
				  forested(bearing: right, distance: row.distance, elevation: high) else { return true }
			let width = row.distance * spokeWidth * .pi / 180
			let sunOnRight = sin((sunBearing - middle) * .pi / 180) > 0
			let uv = LookoutForest.rowCoordinates(offset: row.offset, width: width, distance: row.distance, sunOnRight: sunOnRight)
			func at(_ bearing: Double, _ elevation: Double) -> SIMD3<Double> {
				let radians = bearing * .pi / 180
				return SIMD3(sin(radians) * row.distance, elevation, cos(radians) * row.distance)
			}
			// Sunk a little into the ground, standing the row's height above it.
			let start = UInt32(rowPositions.count)
			rowPositions += [
				place(at(left, low - 2)), place(at(right, high - 2)),
				place(at(right, high - 2 + tall)), place(at(left, low - 2 + tall))
			]
			rowUVs += [SIMD2(uv.u0, uv.v0), SIMD2(uv.u1, uv.v0), SIMD2(uv.u1, uv.v1), SIMD2(uv.u0, uv.v1)]
			rowIndices += [start, start + 1, start + 2, start, start + 2, start + 3]
			triangles += 2
			rows += 1
			return true
		}
		if cancelled { return nil }
		Logger.services.info("🎬 [Cinema] Lookout forest: \(trees, privacy: .public) near trees and \(rows, privacy: .public) rows in view, \(triangles, privacy: .public) triangles")

		var treePart: LookoutForestMesh.Part?
		if trees > 0, let palette = LookoutForest.palette() {
			treePart = .init(positions: treePositions, textureCoordinates: treeUVs, indices: (0..<UInt32(treePositions.count)).map { $0 }, texture: palette)
		}
		var rowPart: LookoutForestMesh.Part?
		if rows > 0, let texture = LookoutForest.rowTexture() {
			rowPart = .init(positions: rowPositions, textureCoordinates: rowUVs, indices: rowIndices, texture: texture)
		}
		guard treePart != nil || rowPart != nil else { return nil }
		return LookoutForestMesh(trees: treePart, rows: rowPart)
	}

	/// What's known about each sample's ground, for the shading.
	private struct Ground {
		let elevations: [Float]
		let covers: [OfflineLandCover?]
		/// Each ring's distance from the site.
		let distances: [Double]
		let lowest: Float
		let highest: Float
		let latitude: Double
		/// The bearing the cab faces; the painted sun is placed from it.
		let heading: Double
	}

	/// One pixel per sample: the ground's color, lit from the painted sun and fading into the haze
	/// with distance. The sunset warms the light a little; it used to turn every green to olive and
	/// tan, so the view read as desert.
	private static func shade(local: [SIMD3<Double>], ground: Ground, distances: [Double], sun: (azimuth: Float, elevation: Float)) -> CGImage? {
		let columns = spokes + 1
		let sunAzimuth = (Double(sun.azimuth) + ground.heading) * .pi / 180
		let sunElevation = Double(sun.elevation) * .pi / 180
		let light = SIMD3<Double>(sin(sunAzimuth) * cos(sunElevation), sin(sunElevation), cos(sunAzimuth) * cos(sunElevation))
		let haze = LookoutForest.hazeColor
		let sunlight = SIMD3<Double>(1.0, 0.88, 0.76)
		let range = Double(max(1, ground.highest - ground.lowest))

		var pixels = [UInt8](repeating: 255, count: rings * columns * 4)
		for ring in 0..<rings {
			let distance = distances[ring]
			for spoke in 0..<columns {
				let index = ring * columns + spoke
				// The slope from the neighbors along the ring and out along the spoke.
				let east = local[ring * columns + (spoke + 1) % spokes] - local[ring * columns + (spoke + spokes - 1) % spokes]
				let out = local[min(rings - 1, ring + 1) * columns + spoke] - local[max(0, ring - 1) * columns + spoke]
				var normal = simd_cross(out, east)
				if normal.y < 0 { normal = -normal }
				let length = simd_length(normal)
				normal = length > 0 ? normal / length : SIMD3(0, 1, 0)

				let height = Double(ground.elevations[index])
				let t = (height - Double(ground.lowest)) / range
				var color = LookoutGroundColor.color(cover: ground.covers[index], elevation: height, latitude: ground.latitude, heightFraction: t)
				let lit = max(0, simd_dot(normal, light))
				color *= 0.5 + 0.5 * lit * sunlight
				let fog = 1 - exp(-distance / LookoutForest.hazeDistance)
				color = simd_mix(color, haze, SIMD3(repeating: fog))

				// Ring 0 on the bottom row: texture v runs up from the bottom of the image.
				let row = rings - 1 - ring
				let offset = (row * columns + spoke) * 4
				pixels[offset] = UInt8(clamping: Int(min(1, color.x) * 255))
				pixels[offset + 1] = UInt8(clamping: Int(min(1, color.y) * 255))
				pixels[offset + 2] = UInt8(clamping: Int(min(1, color.z) * 255))
			}
		}
		let space = CGColorSpaceCreateDeviceRGB()
		return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
			guard let context = CGContext(data: bytes.baseAddress, width: columns, height: rings, bitsPerComponent: 8, bytesPerRow: columns * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
			return context.makeImage()
		}
	}

	/// The terrain as an entity, unlit since its light is painted in.
	@MainActor
	static func entity(for model: LookoutTerrainModel) async throws -> ModelEntity {
		var descriptor = MeshDescriptor(name: "lookoutTerrain")
		descriptor.positions = MeshBuffer(model.positions)
		descriptor.textureCoordinates = MeshBuffer(model.textureCoordinates)
		descriptor.primitives = .triangles(model.indices)
		// Made off the main thread, so the immersive space keeps its frame rate while it's made.
		let mesh = try await MeshResource(from: [descriptor])
		let texture = try await TextureResource(image: model.texture, options: .init(semantic: .color))
		var material = UnlitMaterial()
		material.color = .init(tint: .white, texture: .init(texture))
		material.faceCulling = .none
		let entity = ModelEntity(mesh: mesh, materials: [material])
		entity.name = "LookoutTerrain"
		// The forest is extra scenery: if it can't be made, the terrain still shows without it.
		if let forest = model.trees {
			do {
				if let trees = forest.trees {
					// No mipmaps: smaller levels would blend the palette's shades together on far trees.
					entity.addChild(try await part(trees, name: "LookoutTrees", mipmaps: false, cutout: false))
				}
				if let rows = forest.rows {
					entity.addChild(try await part(rows, name: "LookoutForestRows", mipmaps: true, cutout: true))
				}
			} catch {
				Logger.services.error("🎬 [Cinema] Couldn't make the lookout's trees: \(error.localizedDescription, privacy: .public)")
			}
		}
		return entity
	}

	/// One part of the forest as an entity, unlit like the terrain. The rows' texture is see-through
	/// above the treetops, cut out rather than blended so the rows needn't be sorted.
	@MainActor
	private static func part(_ part: LookoutForestMesh.Part, name: String, mipmaps: Bool, cutout: Bool) async throws -> ModelEntity {
		var descriptor = MeshDescriptor(name: name)
		descriptor.positions = MeshBuffer(part.positions)
		descriptor.textureCoordinates = MeshBuffer(part.textureCoordinates)
		descriptor.primitives = .triangles(part.indices)
		let texture = try await TextureResource(image: part.texture, options: .init(semantic: .color, mipmapsMode: mipmaps ? .allocateAndGenerateAll : .none))
		var material = UnlitMaterial()
		material.color = .init(tint: .white, texture: .init(texture))
		material.faceCulling = .none
		if cutout {
			material.blending = .transparent(opacity: .init(floatLiteral: 1))
			material.opacityThreshold = 0.5
		}
		let entity = ModelEntity(mesh: try await MeshResource(from: [descriptor]), materials: [material])
		entity.name = name
		return entity
	}

	/// Elevations from the tiles, keeping each tile for the rings that share it.
	private final class Sampler {
		let source: any ElevationTileSource
		private var tiles: [String: ElevationTile?] = [:]

		init(source: any ElevationTileSource) {
			self.source = source
		}

		func elevation(latitude: Double, longitude: Double, zoom: Int) async -> Float? {
			let pixel = TerrainStore.tilePixel(latitude: latitude, longitude: longitude, z: zoom, size: TerrainStore.tileSize)
			let key = "\(zoom)/\(pixel.x)/\(pixel.y)"
			let tile: ElevationTile?
			if let cached = tiles[key] {
				tile = cached
			} else {
				tile = await source.elevationTile(z: zoom, x: pixel.x, y: pixel.y, margin: 1)
				tiles[key] = tile
			}
			guard let tile else { return nil }
			return TerrainStore.sample(tile, px: pixel.px, py: pixel.py)
		}
	}
}
#endif
