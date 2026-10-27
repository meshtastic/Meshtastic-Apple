//
//  WeatherRadarTileOverlay.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
//  NOAA's NEXRAD base reflectivity for the lower 48 states, from NCEP's map server.
//  NOAA data is public domain; the server asks for nothing but reasonable use, so tiles
//  stop at zoom 12 and refresh only every few minutes.
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
	init(refreshPeriod: Int) {
		self.refreshPeriod = refreshPeriod
		super.init(urlTemplate: nil)
		canReplaceMapContent = false
		maximumZ = 12
	}

	private let refreshPeriod: Int

	override func url(forTilePath path: MKTileOverlayPath) -> URL {
		Self.url(for: path, refreshPeriod: refreshPeriod)
	}

	/// Pixels across a smoothed tile: twice the tile size, so the rounded edges stay crisp on a
	/// Retina screen.
	static let smoothTileEdge = 512

	/// Zoomed in past the radar's own cells, asks for the cells and draws them smooth; further
	/// out, a pixel covers a cell or more and the server's tile is used as is.
	override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
		let bounds = Self.mercatorBounds(x: path.x, y: path.y, z: path.z)
		let edge = Self.smoothTileEdge
		guard let grid = WeatherRadarCellGrid(bounds: bounds, outputWidth: edge, outputHeight: edge) else {
			super.loadTile(at: path, result: result)
			return
		}
		let url = WeatherRadar.imageURL(mercatorBounds: grid.paddedBounds, width: grid.requestWidth, height: grid.requestHeight, refreshPeriod: refreshPeriod)
		Task.detached(priority: .utility) {
			do {
				let (data, response) = try await URLSession.shared.data(from: url)
				guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
					throw URLError(.badServerResponse)
				}
				guard let source = CGImageSourceCreateWithData(data as CFData, nil),
					  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
					  let smooth = WeatherRadarSmoothing.smooth(image, grid: grid, width: edge, height: edge),
					  let png = Self.pngData(smooth) else { throw URLError(.cannotDecodeContentData) }
				result(png, nil)
			} catch {
				result(nil, error)
			}
		}
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
