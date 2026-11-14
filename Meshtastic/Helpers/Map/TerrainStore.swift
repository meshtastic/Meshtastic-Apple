//
//  TerrainStore.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/16/26.
//
//  Serves elevation grids from a region's downloaded Mapterhorn terrain archives.
//  The actor keeps the archives and caches; decoding and resampling run off it, in
//  parallel, and off the main actor, so map rendering never blocks on it. One store
//  is shared by the 2D map, the 3D map and the cinema. Consumers request
//  `ElevationTile`s for any map zoom: requests above the archived max zoom are
//  answered by bilinear-sampling the covering ancestor tile (standard DEM
//  overzoom), so terrain keeps rendering at street-level zooms.
//

import CoreLocation
import Foundation
import OSLog

/// One region's terrain data: the archive locations plus the coverage box.
struct TerrainSource: Sendable, Equatable {
	let globalURL: URL
	/// High-resolution extracts, one per Mapterhorn z6 archive the region reaches.
	let regionalURLs: [URL]
	let bounds: GeoBounds

	init(globalURL: URL, regionalURLs: [URL], bounds: GeoBounds) {
		self.globalURL = globalURL
		self.regionalURLs = regionalURLs
		self.bounds = bounds
	}

	init(globalURL: URL, regionalURL: URL?, bounds: GeoBounds) {
		self.init(globalURL: globalURL, regionalURLs: regionalURL.map { [$0] } ?? [], bounds: bounds)
	}
}

actor TerrainStore {

	/// The store the app reads downloaded terrain through, so the 2D map, the 3D map and the
	/// cinema share one cache of decoded tiles instead of each decoding the same ones.
	static let shared = TerrainStore()

	/// Output grid edge length (samples per tile, before margin). Mapterhorn tiles
	/// are 512px; sampling to 256 quarters the decode-to-consumer cost and is
	/// indistinguishable under hillshade/contour rendering.
	static let tileSize = 256

	private struct OpenSource {
		let archive: PMTilesArchive
		let regionals: [PMTilesArchive]
		let bounds: GeoBounds
		var maxZoom: Int { regionals.map { Int($0.header.maxZoom) }.reduce(Int(archive.header.maxZoom), max) }

	}

	private var sources: [OpenSource] = []
	private var configuredSources: [TerrainSource] = []
	/// Bumped when the sources change, so a decode or resample started before isn't cached after.
	private var generation = 0
	private struct TileKey: Hashable {
		let z: Int
		let x: Int
		let y: Int
	}
	/// A decoded raw Mapterhorn grid: its edge length and elevations.
	private typealias Grid = (size: Int, elevations: [Float])
	/// Decoded raw grids, LRU-evicted. A 512 px grid is about 1 MB.
	private var decodeCache: [TileKey: Grid] = [:]
	private var decodeOrder: [TileKey] = []
	private let decodeCacheLimit = 64
	/// Decodes running, so a second request for the same tile waits for the first.
	private var decoding: [TileKey: Task<Grid?, Never>] = [:]
	/// Resampled tiles as handed out, LRU-evicted: callers often ask for the same tile again.
	private struct ElevationKey: Hashable {
		let z: Int
		let x: Int
		let y: Int
		let margin: Int
	}
	private var tileCache: [ElevationKey: ElevationTile] = [:]
	private var tileOrder: [ElevationKey] = []
	private let tileCacheLimit = 64

	/// (Re)points the store at the given terrain sources. Cheap when unchanged.
	func configure(sources newSources: [TerrainSource]) {
		guard newSources != configuredSources else { return }
		configuredSources = newSources
		generation += 1
		decodeCache.removeAll()
		decodeOrder.removeAll()
		decoding.removeAll()
		tileCache.removeAll()
		tileOrder.removeAll()
		sources = newSources.compactMap { source in
			guard let archive = PMTilesArchive(url: source.globalURL) else {
				Logger.services.error("🗺️ [Terrain] Could not open terrain archive at \(source.globalURL.lastPathComponent, privacy: .public)")
				return nil
			}
			let regionals = source.regionalURLs.compactMap { PMTilesArchive(url: $0) }
			return OpenSource(archive: archive, regionals: regionals, bounds: source.bounds)
		}
	}

	var hasSources: Bool { !sources.isEmpty }

	/// The finest zoom any configured archive carries, nil with no archives.
	func finestDataZoom() -> Int? {
		sources.map(\.maxZoom).max()
	}

	/// The deepest zoom with real elevation data for a tile: the regional archive's when it reaches
	/// this tile, else the global one's. Nil when no region covers the tile. Past it, tiles are the
	/// data stretched (see `elevationTile`).
	func dataMaxZoom(z: Int, x: Int, y: Int) -> Int? {
		source(covering: z, x: x, y: y).map { Self.dataMaxZoom(open: $0, z: z, x: x, y: y) }
	}

	/// The deepest max zoom of the regional archives that have this tile or one of its ancestors in
	/// their zoom range; else the global archive's. A regional header's bounds are the area asked
	/// for, not where tiles are: Mapterhorn has none over the sea, and none at all in z6 tiles it
	/// has no regional archive for, so a tile there falls back to global.
	private static func dataMaxZoom(open: OpenSource, z: Int, x: Int, y: Int) -> Int {
		let tile = tileBounds(z: z, x: x, y: y)
		var deepest: Int?
		for regional in open.regionals where intersects(regional.header.bounds, tile) {
			let top = Int(regional.header.maxZoom)
			let bottom = Int(regional.header.minZoom)
			guard z >= bottom, top > deepest ?? Int.min else { continue }
			for zoom in stride(from: min(z, top), through: bottom, by: -1)
			where regional.hasTile(z: UInt8(zoom), x: UInt32(x >> (z - zoom)), y: UInt32(y >> (z - zoom))) {
				deepest = top
				break
			}
		}
		return deepest ?? Int(open.archive.header.maxZoom)
	}

	/// Whether any configured region covers the given tile at all.
	func covers(z: Int, x: Int, y: Int) -> Bool {
		source(covering: z, x: x, y: y) != nil
	}

	/// The coverage box of the region covering this tile, for consumers that
	/// clip rendering to the downloaded boundary.
	func coverage(z: Int, x: Int, y: Int) -> GeoBounds? {
		source(covering: z, x: x, y: y)?.bounds
	}

	/// Lon/lat box of a Web-Mercator tile.
	static func tileBounds(z: Int, x: Int, y: Int) -> GeoBounds {
		GeoBounds.tile(z: z, x: x, y: y)
	}

	/// The elevation grid for a map tile at any zoom, with `margin` edge pixels
	/// sampled from neighbors (edge-clamped at coverage boundaries). Nil when no
	/// configured region covers the tile or nothing decodes. The tiles are decoded
	/// and resampled off the actor, so calls from several tasks run in parallel.
	nonisolated func elevationTile(z: Int, x: Int, y: Int, margin: Int = 1) async -> ElevationTile? {
		switch await prepare(z: z, x: x, y: y, margin: margin) {
		case nil:
			return nil
		case .cached(let tile):
			return tile
		case .sample(let input):
			let tile = Self.resample(input, z: z, x: x, y: y, margin: margin)
			await remember(tile, margin: margin, generation: input.generation)
			return tile
		}
	}

	/// A tile ready to hand out, or what's needed to sample it.
	private enum Prepared: Sendable {
		case cached(ElevationTile)
		case sample(SampleInput)
	}

	/// The data tile a map tile is sampled from, where in it, and the decoded grids it reaches into.
	private struct SampleInput: Sendable {
		let dataZoom: Int
		let dataX: Int
		let dataY: Int
		/// How many map tiles per data tile edge.
		let scale: Int
		/// The map tile's sub-rect within the data tile, in [0, 1).
		let fracX: Double
		let fracY: Double
		let tilePx: Int
		let base: [Float]
		/// The neighbors the margin reaches into, by tile. One missing failed to decode or is past
		/// the world's edge.
		let grids: [TileKey: [Float]]
		let generation: Int
	}

	/// Finds the cached tile, or decodes the data tile and the neighbors the samples reach into, all
	/// at once.
	private func prepare(z: Int, x: Int, y: Int, margin: Int) async -> Prepared? {
		let key = ElevationKey(z: z, x: x, y: y, margin: margin)
		if let tile = tileCache[key] {
			touch(key, in: &tileOrder)
			return .cached(tile)
		}
		guard let open = source(covering: z, x: x, y: y) else { return nil }
		let generation = self.generation

		// Clamp to the data's max zoom here: above it, sample the covering ancestor. Per tile, so
		// where no regional archive has data the global archive's is used.
		let dataZoom = min(z, Self.dataMaxZoom(open: open, z: z, x: x, y: y))
		let zoomDelta = z - dataZoom
		let scale = 1 << zoomDelta
		let dataX = x >> zoomDelta
		let dataY = y >> zoomDelta
		let fracX = Double(x - dataX * scale) / Double(scale)
		let fracY = Double(y - dataY * scale) / Double(scale)

		let baseKey = TileKey(z: dataZoom, x: dataX, y: dataY)
		guard let base = await grid(open: open, key: baseKey).value() else { return nil }
		let tilePx = base.size
		// Which neighbors the samples, margin and all, walk into: at most one tile each way.
		let step = Double(tilePx) / Double(scale) / Double(Self.tileSize)
		let last = Self.tileSize + margin - 1
		func reach(_ origin: Double) -> ClosedRange<Int> {
			let low = Int((origin + (Double(-margin) + 0.5) * step - 0.5).rounded(.down))
			let high = Int((origin + (Double(last) + 0.5) * step - 0.5).rounded(.down)) + 1
			return (low < 0 ? -1 : 0)...(high >= tilePx ? 1 : 0)
		}
		let maxIndex = (1 << dataZoom) - 1
		var neighbors: [TileKey] = []
		for dy in reach(fracY * Double(tilePx)) {
			for dx in reach(fracX * Double(tilePx)) where dx != 0 || dy != 0 {
				neighbors.append(TileKey(z: dataZoom, x: min(max(dataX + dx, 0), maxIndex), y: min(max(dataY + dy, 0), maxIndex)))
			}
		}
		// Every neighbor's decode starts before any is waited on.
		let pending = neighbors.map { ($0, grid(open: open, key: $0)) }
		var grids = [baseKey: base.elevations]
		for (key, lookup) in pending where grids[key] == nil {
			if let neighbor = await lookup.value() {
				grids[key] = neighbor.elevations
			}
		}
		return .sample(SampleInput(
			dataZoom: dataZoom, dataX: dataX, dataY: dataY, scale: scale, fracX: fracX, fracY: fracY,
			tilePx: tilePx, base: base.elevations, grids: grids, generation: generation
		))
	}

	/// Bilinear samples of the data tile over the map tile, walking into a neighbor where a sample
	/// leaves the data tile, and clamping to the data tile's edge where that neighbor is missing.
	private static func resample(_ input: SampleInput, z: Int, x: Int, y: Int, margin: Int) -> ElevationTile {
		let size = tileSize
		let grid = size + 2 * margin
		let tilePx = input.tilePx
		let span = Double(tilePx) / Double(input.scale)
		let originX = input.fracX * Double(tilePx)
		let originY = input.fracY * Double(tilePx)
		let step = span / Double(size)
		let maxIndex = (1 << input.dataZoom) - 1
		let base = input.base
		var elevations = [Float](repeating: 0, count: grid * grid)

		// Integer point sample: walks into the neighbor tile when the coordinate
		// leaves this one. When the neighbor is missing, clamps to THIS tile's
		// nearest edge (never the wrapped opposite edge).
		func point(_ ix: Int, _ iy: Int) -> Float {
			var tileX = input.dataX, tileY = input.dataY, lx = ix, ly = iy
			if lx < 0 { tileX -= 1; lx += tilePx } else if lx >= tilePx { tileX += 1; lx -= tilePx }
			if ly < 0 { tileY -= 1; ly += tilePx } else if ly >= tilePx { tileY += 1; ly -= tilePx }
			if tileX != input.dataX || tileY != input.dataY {
				let key = TileKey(z: input.dataZoom, x: min(max(tileX, 0), maxIndex), y: min(max(tileY, 0), maxIndex))
				if let neighbor = input.grids[key] {
					return neighbor[ly * tilePx + lx]
				}
				// Missing neighbor: clamp the ORIGINAL coordinate into the base tile.
				let cx = min(max(ix, 0), tilePx - 1)
				let cy = min(max(iy, 0), tilePx - 1)
				return base[cy * tilePx + cx]
			}
			return base[ly * tilePx + lx]
		}

		for gy in 0..<grid {
			let sy = originY + (Double(gy - margin) + 0.5) * step - 0.5
			let y0 = Int(sy.rounded(.down))
			let ty = Float(sy - Double(y0))
			for gx in 0..<grid {
				let sx = originX + (Double(gx - margin) + 0.5) * step - 0.5
				let x0 = Int(sx.rounded(.down))
				let tx = Float(sx - Double(x0))
				let p00 = point(x0, y0), p10 = point(x0 + 1, y0)
				let p01 = point(x0, y0 + 1), p11 = point(x0 + 1, y0 + 1)
				let top = p00 + (p10 - p00) * tx
				let bottom = p01 + (p11 - p01) * tx
				elevations[gy * grid + gx] = top + (bottom - top) * ty
			}
		}
		return ElevationTile(z: z, x: x, y: y, size: size, margin: margin, elevations: elevations)
	}

	/// Keeps a resampled tile for the next request, unless the sources changed meanwhile.
	private func remember(_ tile: ElevationTile, margin: Int, generation: Int) {
		guard generation == self.generation else { return }
		let key = ElevationKey(z: tile.z, x: tile.x, y: tile.y, margin: margin)
		guard tileCache[key] == nil else { return }
		tileCache[key] = tile
		tileOrder.append(key)
		if tileOrder.count > tileCacheLimit {
			tileCache.removeValue(forKey: tileOrder.removeFirst())
		}
	}

	// MARK: - Point queries

	/// What a downloaded region holds for one tile a coverage estimate needs.
	enum CoverageTile: Sendable {
		/// The raw, undecoded Mapterhorn tile.
		case data(Data)
		/// A region holds the whole tile at this zoom but has no tile for it. Mapterhorn has no sea
		/// tiles, so this is sea.
		case sea
		/// No region holds this tile.
		case notHeld
	}

	/// The tile at exactly `z/x/y` from a downloaded region, undecoded and not cached, so a coverage
	/// estimate can decode its tiles in parallel off this actor.
	func coverageTile(z: Int, x: Int, y: Int) -> CoverageTile {
		guard let open = source(covering: z, x: x, y: y), z <= Self.dataMaxZoom(open: open, z: z, x: x, y: y) else { return .notHeld }
		if let data = tileData(open: open, z: z, x: x, y: y) { return .data(data) }
		let carriesZoom = z >= Int(open.archive.header.minZoom) && z <= Int(open.archive.header.maxZoom)
		return carriesZoom && Self.contains(open.bounds, Self.tileBounds(z: z, x: x, y: y)) ? .sea : .notHeld
	}

	/// Zoom used for single-coordinate elevation lookups: the finest zoom the
	/// global archive always carries (~30 m data), plenty for a site elevation.
	static let pointQueryZoom = 12

	/// A coordinate located within a tile grid: the tile indices plus the
	/// fractional (sample-centered) pixel position inside it.
	struct TilePixel {
		let x: Int
		let y: Int
		let px: Double
		let py: Double
	}

	/// Ground elevation in meters at a coordinate, or nil when no downloaded
	/// terrain region covers it.
	func elevation(at coordinate: CLLocationCoordinate2D) async -> Double? {
		await elevations(at: [coordinate])[0]
	}

	/// `elevation(at:)` for each coordinate, in one trip to the store. Each tile is
	/// sampled once for all the coordinates in it, so thousands of points cost a
	/// few tiles, not a tile each.
	func elevations(at coordinates: [CLLocationCoordinate2D]) async -> [Double?] {
		let z = Self.pointQueryZoom
		var tiles: [TileKey: ElevationTile?] = [:]
		var heights: [Double?] = []
		heights.reserveCapacity(coordinates.count)
		for coordinate in coordinates {
			let pixel = Self.tilePixel(latitude: coordinate.latitude, longitude: coordinate.longitude, z: z, size: Self.tileSize)
			// Edge tiles are edge-clamped, so also require the coordinate itself to
			// sit inside the covering region's box — never report a clamped border
			// value for a point outside the download.
			guard let box = coverage(z: z, x: pixel.x, y: pixel.y),
				  coordinate.latitude >= box.minLat, coordinate.latitude <= box.maxLat,
				  coordinate.longitude >= box.minLon, coordinate.longitude <= box.maxLon else {
				heights.append(nil)
				continue
			}
			let key = TileKey(z: z, x: pixel.x, y: pixel.y)
			let tile: ElevationTile?
			if let sampled = tiles[key] {
				tile = sampled
			} else {
				tile = await elevationTile(z: z, x: pixel.x, y: pixel.y, margin: 1)
				tiles[key] = tile
			}
			heights.append(tile.map { Double(Self.sample($0, px: pixel.px, py: pixel.py)) })
		}
		return heights
	}

	/// The Web-Mercator tile containing a coordinate at zoom `z`, plus the
	/// coordinate's fractional pixel position (sample-centered) within a
	/// `size`-sample grid for that tile.
	static func tilePixel(latitude: Double, longitude: Double, z: Int, size: Int) -> TilePixel {
		let n = Double(1 << z)
		// Clamp to the Web-Mercator latitude limit so the y math stays finite.
		let lat = min(max(latitude, -85.05112878), 85.05112878)
		let lon = min(max(longitude, -180), 180)
		let xt = (lon + 180) / 360 * n
		let latRad = lat * .pi / 180
		let yt = (1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n
		let maxIndex = (1 << z) - 1
		let x = min(max(Int(xt.rounded(.down)), 0), maxIndex)
		let y = min(max(Int(yt.rounded(.down)), 0), maxIndex)
		let px = (xt - Double(x)) * Double(size) - 0.5
		let py = (yt - Double(y)) * Double(size) - 0.5
		return TilePixel(x: x, y: y, px: px, py: py)
	}

	/// Bilinear sample of a tile's elevation grid at a fractional pixel position
	/// (grid coordinates clamp at the margin, matching `gridElevation`).
	static func sample(_ tile: ElevationTile, px: Double, py: Double) -> Float {
		let x0 = Int(px.rounded(.down))
		let y0 = Int(py.rounded(.down))
		let tx = Float(px - Double(x0))
		let ty = Float(py - Double(y0))
		let p00 = tile.gridElevation(x: x0, y: y0)
		let p10 = tile.gridElevation(x: x0 + 1, y: y0)
		let p01 = tile.gridElevation(x: x0, y: y0 + 1)
		let p11 = tile.gridElevation(x: x0 + 1, y: y0 + 1)
		let top = p00 + (p10 - p00) * tx
		let bottom = p01 + (p11 - p01) * tx
		return top + (bottom - top) * ty
	}

	/// Meters-per-sample for an `ElevationTile` at the given zoom/latitude — the
	/// ground resolution consumers need for slope math.
	static func metersPerSample(z: Int, y: Int, size: Int) -> Double {
		let n = Double(1 << z)
		let latitude = atan(sinh(.pi * (1 - 2 * (Double(y) + 0.5) / n))) * 180 / .pi
		let metersPerTile = 40_075_016.686 * cos(latitude * .pi / 180) / n
		return metersPerTile / Double(size)
	}

	/// A decoded grid already cached, a decode running, or nothing to decode.
	private enum GridLookup {
		case ready(Grid)
		case running(Task<Grid?, Never>)
		case missing

		func value() async -> Grid? {
			switch self {
			case .ready(let grid): grid
			case .running(let task): await task.value
			case .missing: nil
			}
		}
	}

	/// The raw decoded Mapterhorn grid for a data tile, preferring the regional archive when it has
	/// the tile: cached (LRU, hits move to the back), already decoding, or decoded now off the actor.
	private func grid(open: OpenSource, key: TileKey) -> GridLookup {
		if let cached = decodeCache[key] {
			touch(key, in: &decodeOrder)
			return .ready(cached)
		}
		if let running = decoding[key] { return .running(running) }
		guard let data = tileData(open: open, z: key.z, x: key.x, y: key.y) else { return .missing }
		let generation = self.generation
		let task = Task { () -> Grid? in
			let decoded = await Task.detached(priority: Task.currentPriority) { TerrariumDecoder.decode(tileData: data) }.value
			finishDecode(key, decoded, generation: generation)
			return decoded
		}
		decoding[key] = task
		return .running(task)
	}

	private func finishDecode(_ key: TileKey, _ decoded: Grid?, generation: Int) {
		// Sources changed meanwhile: the caches were emptied and this tile may be another region's.
		guard generation == self.generation else { return }
		decoding[key] = nil
		guard let decoded else { return }
		decodeCache[key] = decoded
		decodeOrder.append(key)
		if decodeOrder.count > decodeCacheLimit {
			decodeCache.removeValue(forKey: decodeOrder.removeFirst())
		}
	}

	/// Moves a cache hit to the back of its LRU order.
	private func touch<Key: Hashable>(_ key: Key, in order: inout [Key]) {
		if let position = order.firstIndex(of: key), position != order.count - 1 {
			order.remove(at: position)
			order.append(key)
		}
	}

	/// A tile's bytes, from a regional archive that has the tile, else the global one.
	private func tileData(open: OpenSource, z: Int, x: Int, y: Int) -> Data? {
		let tile = Self.tileBounds(z: z, x: x, y: y)
		for regional in open.regionals where z >= Int(regional.header.minZoom) && z <= Int(regional.header.maxZoom)
			&& Self.intersects(regional.header.bounds, tile) {
			if let data = regional.tileData(z: UInt8(z), x: UInt32(x), y: UInt32(y)) { return data }
		}
		return open.archive.tileData(z: UInt8(z), x: UInt32(x), y: UInt32(y))
	}

	/// Whether two boxes overlap.
	static func intersects(_ a: GeoBounds, _ b: GeoBounds) -> Bool {
		a.minLon < b.maxLon && a.maxLon > b.minLon && a.minLat < b.maxLat && a.maxLat > b.minLat
	}

	/// Whether `bounds` holds all of `tile`.
	static func contains(_ bounds: GeoBounds, _ tile: GeoBounds) -> Bool {
		bounds.minLon <= tile.minLon && bounds.maxLon >= tile.maxLon && bounds.minLat <= tile.minLat && bounds.maxLat >= tile.maxLat
	}

	/// The configured source to read a tile from. A center test left border tiles either spilling
	/// past the region boundary or gapped inside it; intersection + consumer-side clipping renders
	/// exactly to the boundary. When regions overlap, a source that contains the whole tile wins,
	/// so a tile is never clipped to a smaller region's box while a bigger one covers all of it.
	private func source(covering z: Int, x: Int, y: Int) -> OpenSource? {
		let tile = Self.tileBounds(z: z, x: x, y: y)
		return Self.preferredSourceIndex(tile: tile, sources: sources.map { ($0.bounds, $0.maxZoom) }).map { sources[$0] }
	}

	/// Which source serves a tile: among sources that contain the whole tile, the one with the
	/// finest data (first listed on a tie); otherwise the one overlapping the tile the most. Nil
	/// when no source touches the tile.
	static func preferredSourceIndex(tile: GeoBounds, sources: [(bounds: GeoBounds, maxZoom: Int)]) -> Int? {
		var best: (index: Int, maxZoom: Int)?
		for (index, source) in sources.enumerated() {
			guard contains(source.bounds, tile) else { continue }
			if let current = best, source.maxZoom <= current.maxZoom { continue }
			best = (index, source.maxZoom)
		}
		if let best { return best.index }
		var bestOverlap: (index: Int, area: Double)?
		for (index, source) in sources.enumerated() {
			let b = source.bounds
			guard tile.minLon <= b.maxLon, tile.maxLon >= b.minLon, tile.minLat <= b.maxLat, tile.maxLat >= b.minLat else { continue }
			let area = (min(tile.maxLon, b.maxLon) - max(tile.minLon, b.minLon)) * (min(tile.maxLat, b.maxLat) - max(tile.minLat, b.minLat))
			if let current = bestOverlap, area <= current.area { continue }
			bestOverlap = (index, area)
		}
		return bestOverlap?.index
	}
}
