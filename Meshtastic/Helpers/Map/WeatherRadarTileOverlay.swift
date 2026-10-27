//
//  WeatherRadarTileOverlay.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
//  NOAA's NEXRAD base reflectivity for the lower 48 states, from NCEP's map server.
//  NOAA data is public domain; the server asks for nothing but reasonable use, so tiles are
//  fetched down to zoom 12 only and refresh only every few minutes. Closer in, a tile is cut
//  from the zoom 12 tile that contains it.
//

import Foundation
import ImageIO
import MapKit

enum WeatherRadar {
	/// How often the radar is fetched again while it's shown. NOAA updates it every few minutes.
	static let refreshInterval: TimeInterval = 5 * 60
	/// Drawn over the map, not instead of it.
	static let opacity: CGFloat = 0.6
	/// Half the width of the world in EPSG:3857 meters.
	static let mercatorWorldHalf = 20_037_508.342789244

	/// The current refresh period, used to fetch new tiles when it changes.
	static func refreshPeriod(at date: Date = .now) -> Int {
		Int(date.timeIntervalSince1970 / refreshInterval)
	}

	/// A box around the lower 48 states. It keeps out Alaska, Hawaii and Puerto Rico, which this
	/// radar layer doesn't cover, but takes in parts of Canada and Mexico, so the country decides too.
	static func covers(_ coordinate: CLLocationCoordinate2D) -> Bool {
		(24.0...50.0).contains(coordinate.latitude) && (-125.0 ... -66.0).contains(coordinate.longitude)
	}

	/// Offered only in the lower 48: a location in the box whose country is the US, or, with no
	/// location to go on, a phone set to the US. The radio's LoRa region doesn't decide it; the US
	/// region is used across the Americas.
	static func isOffered(location: CLLocationCoordinate2D?, countryCode: String?, phoneRegion: Locale.Region?) -> Bool {
		guard let location else { return phoneRegion == .unitedStates }
		return covers(location) && countryCode == "US"
	}

	/// A box's bounds in EPSG:3857 meters, y up. The same Mercator the spatial map's texture is
	/// laid out in, so an image of these bounds lines up with the terrain.
	static func mercatorBounds(for bounds: GeoBounds) -> CGRect {
		let minX = bounds.minLon / 180 * mercatorWorldHalf
		let maxX = bounds.maxLon / 180 * mercatorWorldHalf
		let minY = mercatorWorldHalf * (1 - 2 * SpatialFrame.mercatorY(bounds.minLat))
		let maxY = mercatorWorldHalf * (1 - 2 * SpatialFrame.mercatorY(bounds.maxLat))
		return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
	}

	/// One WMS GetMap of `mercatorBounds` at `width` by `height` pixels, transparent where there is
	/// no rain. The server speaks WMS rather than serving z/x/y tiles, so each image asks for its
	/// own Web Mercator bounds. `refreshPeriod` only changes the URL so caches don't serve an old image.
	static func imageURL(mercatorBounds bounds: CGRect, width: Int, height: Int, refreshPeriod: Int) -> URL {
		let bbox = [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].map { String(format: "%.2f", $0) }.joined(separator: ",")
		var components = URLComponents(string: "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows")!
		components.queryItems = [
			URLQueryItem(name: "SERVICE", value: "WMS"),
			URLQueryItem(name: "VERSION", value: "1.1.0"),
			URLQueryItem(name: "REQUEST", value: "GetMap"),
			URLQueryItem(name: "LAYERS", value: "conus_bref_qcd"),
			URLQueryItem(name: "STYLES", value: ""),
			URLQueryItem(name: "FORMAT", value: "image/png"),
			URLQueryItem(name: "TRANSPARENT", value: "true"),
			URLQueryItem(name: "SRS", value: "EPSG:3857"),
			URLQueryItem(name: "BBOX", value: bbox),
			URLQueryItem(name: "WIDTH", value: String(width)),
			URLQueryItem(name: "HEIGHT", value: String(height)),
			URLQueryItem(name: "period", value: String(refreshPeriod))
		]
		return components.url!
	}
}

/// Whether to offer the radar where the phone is now. The country comes from reverse geocoding,
/// done again only after the phone moves, so checking on every refresh is cheap.
@MainActor
final class WeatherRadarAvailability: ObservableObject {
	static let shared = WeatherRadarAvailability()

	@Published private(set) var isOffered = false
	private var checkedLocation: CLLocation?
	/// How far the phone moves before the country is looked up again.
	private static let recheckDistance: CLLocationDistance = 10_000

	private init() {}

	func refresh() async {
		guard let location = LocationsHandler.shared.manager.location else {
			checkedLocation = nil
			offer(WeatherRadar.isOffered(location: nil, countryCode: nil, phoneRegion: Locale.current.region))
			return
		}
		if let checkedLocation, checkedLocation.distance(from: location) < Self.recheckDistance { return }
		guard WeatherRadar.covers(location.coordinate) else {
			checkedLocation = location
			offer(false)
			return
		}
		// No answer (offline, or the geocoder is busy): keep what was decided before and try again
		// on the next refresh.
		guard let countryCode = try? await CLGeocoder().reverseGeocodeLocation(location).first?.isoCountryCode else { return }
		checkedLocation = location
		offer(WeatherRadar.isOffered(location: location.coordinate, countryCode: countryCode, phoneRegion: Locale.current.region))
	}

	/// Published only when it changes, so a check that finds the same answer redraws nothing.
	private func offer(_ offered: Bool) {
		if isOffered != offered { isOffered = offered }
	}
}

final class WeatherRadarTileOverlay: MKTileOverlay {
	/// NOAA is asked for tiles down to this zoom; closer in, tiles are cut from these.
	static let fetchMaximumZ = 12

	init(refreshPeriod: Int) {
		self.refreshPeriod = refreshPeriod
		super.init(urlTemplate: nil)
		canReplaceMapContent = false
		// MapKit draws nothing past an overlay's maximum zoom rather than stretching its tiles,
		// and on a phone it asks for tiles a level or two past the zoom on screen.
		maximumZ = 21
	}

	private let refreshPeriod: Int

	override func url(forTilePath path: MKTileOverlayPath) -> URL {
		Self.url(for: path, refreshPeriod: refreshPeriod)
	}

	/// Pixels across a smoothed tile: twice the tile size, so the rounded edges stay crisp on a
	/// Retina screen.
	static let smoothTileEdge = 512

	override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
		let refreshPeriod = refreshPeriod
		let edge = Int(tileSize.width * max(path.contentScaleFactor, 1))
		Task.detached(priority: .utility) {
			do {
				guard path.z > Self.fetchMaximumZ else {
					result(try await Self.tileData(x: path.x, y: path.y, z: path.z, refreshPeriod: refreshPeriod), nil)
					return
				}
				let part = WeatherRadarTilePart(x: path.x, y: path.y, z: path.z, fetchZ: Self.fetchMaximumZ)
				let key = Self.url(for: MKTileOverlayPath(x: part.ancestorX, y: part.ancestorY, z: part.ancestorZ, contentScaleFactor: 1), refreshPeriod: refreshPeriod)
				let data = try await Self.ancestors.data(for: key) {
					try await Self.tileData(x: part.ancestorX, y: part.ancestorY, z: part.ancestorZ, refreshPeriod: refreshPeriod)
				}
				guard let image = Self.image(data), let cut = part.cut(from: image, size: edge),
					  let png = Self.pngData(cut) else { throw URLError(.cannotDecodeContentData) }
				result(png, nil)
			} catch {
				result(nil, error)
			}
		}
	}

	/// The zoom 12 tiles that closer tiles are cut from. Many close tiles share one, and MapKit asks
	/// for them all at once, so each is made once and shared.
	private static let ancestors = WeatherRadarAncestorTiles()

	/// A tile at the fetch zoom or further out. Zoomed in past the radar's own cells, asks for the
	/// cells and draws them smooth; further out, a pixel covers a cell or more and the server's
	/// tile is used as is.
	private static func tileData(x: Int, y: Int, z: Int, refreshPeriod: Int) async throws -> Data {
		let bounds = mercatorBounds(x: x, y: y, z: z)
		let edge = smoothTileEdge
		guard let grid = WeatherRadarCellGrid(bounds: bounds, outputWidth: edge, outputHeight: edge) else {
			return try await download(WeatherRadar.imageURL(mercatorBounds: bounds, width: 256, height: 256, refreshPeriod: refreshPeriod))
		}
		let data = try await download(WeatherRadar.imageURL(mercatorBounds: grid.paddedBounds, width: grid.requestWidth, height: grid.requestHeight, refreshPeriod: refreshPeriod))
		guard let image = image(data),
			  let smooth = WeatherRadarSmoothing.smooth(image, grid: grid, width: edge, height: edge),
			  let png = pngData(smooth) else { throw URLError(.cannotDecodeContentData) }
		return png
	}

	private static func download(_ url: URL) async throws -> Data {
		let (data, response) = try await URLSession.shared.data(from: url)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return data
	}

	private static func image(_ data: Data) -> CGImage? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
		return CGImageSourceCreateImageAtIndex(source, 0, nil)
	}

	private static func pngData(_ image: CGImage) -> Data? {
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
		CGImageDestinationAddImage(destination, image, nil)
		return CGImageDestinationFinalize(destination) ? data as Data : nil
	}

	/// One tile's image: a GetMap of the tile's own Web Mercator bounds.
	static func url(for path: MKTileOverlayPath, refreshPeriod: Int) -> URL {
		WeatherRadar.imageURL(mercatorBounds: mercatorBounds(x: path.x, y: path.y, z: path.z), width: 256, height: 256, refreshPeriod: refreshPeriod)
	}

	/// A tile's bounds in EPSG:3857 meters, as minX/minY/maxX/maxY of the rect (y up, unlike map
	/// points). Tile y counts down from the top.
	static func mercatorBounds(x: Int, y: Int, z: Int) -> CGRect {
		let worldHalf = WeatherRadar.mercatorWorldHalf
		let tileSize = worldHalf * 2 / Double(1 << z)
		let minX = -worldHalf + Double(x) * tileSize
		let maxY = worldHalf - Double(y) * tileSize
		return CGRect(x: minX, y: maxY - tileSize, width: tileSize, height: tileSize)
	}
}

/// A tile past the fetch zoom, as part of the tile at that zoom that contains it.
struct WeatherRadarTilePart: Equatable {
	let ancestorX: Int
	let ancestorY: Int
	let ancestorZ: Int
	/// Where the tile sits in its ancestor, as fractions of it, y down.
	let rect: CGRect

	init(x: Int, y: Int, z: Int, fetchZ: Int) {
		let levels = max(z - fetchZ, 0)
		ancestorX = x >> levels
		ancestorY = y >> levels
		ancestorZ = z - levels
		let count = Double(1 << levels)
		rect = CGRect(x: Double(x - (ancestorX << levels)) / count, y: Double(y - (ancestorY << levels)) / count, width: 1 / count, height: 1 / count)
	}

	/// The tile's part of `image`, scaled up to `size` pixels square.
	func cut(from image: CGImage, size: Int) -> CGImage? {
		guard size > 0, let context = CGContext(
			data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else { return nil }
		context.interpolationQuality = .high
		// Core Graphics has y up: the part's top edge goes to the top of the context.
		let scale = Double(size) / rect.width
		context.draw(image, in: CGRect(x: -rect.minX * scale, y: Double(size) - scale * (1 - rect.minY), width: scale, height: scale))
		return context.makeImage()
	}
}

/// The tiles closer tiles are cut from, shared while they're being made and kept for a while.
actor WeatherRadarAncestorTiles {
	/// Enough for a screen of close-in tiles across a couple of refreshes.
	static let limit = 32

	private var tiles: [URL: Task<Data, Error>] = [:]
	private var order: [URL] = []

	func data(for key: URL, make: @escaping @Sendable () async throws -> Data) async throws -> Data {
		if let tile = tiles[key] {
			return try await tile.value
		}
		let tile = Task { try await make() }
		tiles[key] = tile
		order.append(key)
		if order.count > Self.limit {
			tiles[order.removeFirst()] = nil
		}
		do {
			return try await tile.value
		} catch {
			// A failed tile is tried again next time.
			if tiles[key] == tile {
				tiles[key] = nil
				order.removeAll { $0 == key }
			}
			throw error
		}
	}
}
