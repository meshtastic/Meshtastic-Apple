//
//  WeatherRadarTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//

import Foundation
import MapKit
import Testing
@testable import Meshtastic

@Suite("WeatherRadar")
struct WeatherRadarTests {

	@Test func tileBoundsAreWebMercatorMeters() {
		let world = WeatherRadarTileOverlay.mercatorBounds(x: 0, y: 0, z: 0)
		#expect(abs(world.minX + 20_037_508.34) < 0.01)
		#expect(abs(world.maxY - 20_037_508.34) < 0.01)
		#expect(abs(world.maxX - world.minX - 40_075_016.69) < 0.01)

		// Zoom 1, bottom-right: the south-east quarter of the world.
		let quarter = WeatherRadarTileOverlay.mercatorBounds(x: 1, y: 1, z: 1)
		#expect(abs(quarter.minX) < 0.01)
		#expect(abs(quarter.maxY) < 0.01)
	}

	@Test func tileURLAsksForTheTilesBounds() throws {
		let path = MKTileOverlayPath(x: 1, y: 1, z: 1, contentScaleFactor: 1)
		let url = WeatherRadarTileOverlay.url(for: path, refreshPeriod: 42)
		let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
		let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
		#expect(url.host == "opengeo.ncep.noaa.gov")
		#expect(query["LAYERS"] == "conus_bref_qcd")
		#expect(query["SRS"] == "EPSG:3857")
		#expect(query["BBOX"] == "0.00,-20037508.34,20037508.34,0.00")
		#expect(query["period"] == "42")
	}

	@Test func refreshPeriodChangesEveryFiveMinutes() {
		let start = Date(timeIntervalSince1970: 3_000)
		#expect(WeatherRadar.refreshPeriod(at: start) == WeatherRadar.refreshPeriod(at: start.addingTimeInterval(299)))
		#expect(WeatherRadar.refreshPeriod(at: start) + 1 == WeatherRadar.refreshPeriod(at: start.addingTimeInterval(300)))
	}

	@Test func offeredOnlyInTheLowerFortyEight() {
		let seattle = CLLocationCoordinate2D(latitude: 47.61, longitude: -122.33)
		let vancouver = CLLocationCoordinate2D(latitude: 49.28, longitude: -123.12)
		let tijuana = CLLocationCoordinate2D(latitude: 32.51, longitude: -117.04)
		let honolulu = CLLocationCoordinate2D(latitude: 21.31, longitude: -157.86)
		let anchorage = CLLocationCoordinate2D(latitude: 61.22, longitude: -149.90)
		#expect(WeatherRadar.isOffered(location: seattle, countryCode: "US", phoneRegion: .germany))
		// Inside the box, but not the US.
		#expect(!WeatherRadar.isOffered(location: vancouver, countryCode: "CA", phoneRegion: .unitedStates))
		#expect(!WeatherRadar.isOffered(location: tijuana, countryCode: "MX", phoneRegion: .unitedStates))
		// The US, but not the lower 48.
		#expect(!WeatherRadar.isOffered(location: honolulu, countryCode: "US", phoneRegion: .unitedStates))
		#expect(!WeatherRadar.isOffered(location: anchorage, countryCode: "US", phoneRegion: .unitedStates))
		// No country answer yet.
		#expect(!WeatherRadar.isOffered(location: seattle, countryCode: nil, phoneRegion: .unitedStates))

		// No location: the phone's region decides.
		#expect(WeatherRadar.isOffered(location: nil, countryCode: nil, phoneRegion: .unitedStates))
		#expect(!WeatherRadar.isOffered(location: nil, countryCode: nil, phoneRegion: .canada))
	}

	@Test func boxBoundsAreWebMercatorMeters() {
		let worldHalf = WeatherRadar.mercatorWorldHalf
		let world = WeatherRadar.mercatorBounds(for: GeoBounds(minLon: -180, minLat: -85.05, maxLon: 180, maxLat: 85.05))
		#expect(abs(world.minX + worldHalf) < 0.01 && abs(world.maxX - worldHalf) < 0.01)
		// The Mercator limit is a touch short of the world's half height.
		#expect(abs(world.minY + 20_036_051.92) < 0.01 && abs(world.maxY - 20_036_051.92) < 0.01)

		// The square around a 50 km circle on Seattle, as the spatial map boxes it.
		let box = SpatialCircle(latitude: 47.61, longitude: -122.33, radiusMeters: 50_000).bounds
		let bounds = WeatherRadar.mercatorBounds(for: box)
		#expect(abs(bounds.minX + 13_691_877.86) < 0.01)
		#expect(abs(bounds.minY - 5_968_367.61) < 0.01)
		#expect(abs(bounds.maxX + 13_543_548.76) < 0.01)
		#expect(abs(bounds.maxY - 6_116_701.87) < 0.01)
	}

	@Test func imageURLAsksForTheBoundsAtTheSize() throws {
		let worldHalf = WeatherRadar.mercatorWorldHalf
		let url = WeatherRadar.imageURL(mercatorBounds: CGRect(x: 0, y: -worldHalf, width: worldHalf, height: worldHalf), width: 300, height: 200, refreshPeriod: 7)
		let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
		let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
		#expect(query["BBOX"] == "0.00,-20037508.34,20037508.34,0.00")
		#expect(query["WIDTH"] == "300" && query["HEIGHT"] == "200")
		#expect(query["FORMAT"] == "image/png" && query["TRANSPARENT"] == "true")
		#expect(query["period"] == "7")
	}
}
