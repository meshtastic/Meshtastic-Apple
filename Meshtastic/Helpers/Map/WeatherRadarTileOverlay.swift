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
import MapKit

enum WeatherRadar {
	/// How often the radar is fetched again while it's shown. NOAA updates it every few minutes.
	static let refreshInterval: TimeInterval = 5 * 60
	/// Drawn over the map, not instead of it.
	static let opacity: CGFloat = 0.6

	/// The current refresh period, used to fetch new tiles when it changes.
	static func refreshPeriod(at date: Date = .now) -> Int {
		Int(date.timeIntervalSince1970 / refreshInterval)
	}

	/// Roughly the lower 48 states, the area the radar layer covers.
	static func covers(_ coordinate: CLLocationCoordinate2D) -> Bool {
		(24.0...50.0).contains(coordinate.latitude) && (-125.0 ... -66.0).contains(coordinate.longitude)
	}

	/// Offered only where it has data: when the phone is inside the radar's coverage, or, with no
	/// location to go on, when the phone is set to the US. The radio's LoRa region doesn't decide it;
	/// the US region is used across the Americas.
	static func isOffered(location: CLLocationCoordinate2D?, phoneRegion: Locale.Region? = Locale.current.region) -> Bool {
		if let location { return covers(location) }
		return phoneRegion == .unitedStates
	}

	/// `isOffered` for the phone's current location.
	@MainActor static func isOfferedHere() -> Bool {
		isOffered(location: LocationsHandler.currentLocation)
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

	/// The server speaks WMS rather than serving z/x/y tiles, so each tile asks for its own
	/// Web Mercator bounds. `refreshPeriod` only changes the URL so MapKit doesn't reuse old tiles.
	static func url(for path: MKTileOverlayPath, refreshPeriod: Int) -> URL {
		let bounds = mercatorBounds(x: path.x, y: path.y, z: path.z)
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
			URLQueryItem(name: "WIDTH", value: "256"),
			URLQueryItem(name: "HEIGHT", value: "256"),
			URLQueryItem(name: "period", value: String(refreshPeriod))
		]
		return components.url!
	}

	/// A tile's bounds in EPSG:3857 meters, as minX/minY/maxX/maxY of the rect (y up, unlike map
	/// points). Tile y counts down from the top.
	static func mercatorBounds(x: Int, y: Int, z: Int) -> CGRect {
		let worldHalf = 20_037_508.342789244
		let tileSize = worldHalf * 2 / Double(1 << z)
		let minX = -worldHalf + Double(x) * tileSize
		let maxY = worldHalf - Double(y) * tileSize
		return CGRect(x: minX, y: maxY - tileSize, width: tileSize, height: tileSize)
	}
}
