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

	@Test func offeredOnlyWhereTheRadarHasData() {
		let seattle = CLLocationCoordinate2D(latitude: 47.61, longitude: -122.33)
		let vancouver = CLLocationCoordinate2D(latitude: 49.28, longitude: -123.12)
		let mexicoCity = CLLocationCoordinate2D(latitude: 19.43, longitude: -99.13)
		let honolulu = CLLocationCoordinate2D(latitude: 21.31, longitude: -157.86)
		let berlin = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.40)
		#expect(WeatherRadar.isOffered(location: seattle, phoneRegion: .germany))
		#expect(!WeatherRadar.isOffered(location: mexicoCity, phoneRegion: .unitedStates))
		#expect(!WeatherRadar.isOffered(location: honolulu, phoneRegion: .unitedStates))
		#expect(!WeatherRadar.isOffered(location: berlin, phoneRegion: .unitedStates))
		// The box is rough: southern British Columbia falls inside it.
		#expect(WeatherRadar.isOffered(location: vancouver, phoneRegion: .canada))

		// No location: the phone's region decides.
		#expect(WeatherRadar.isOffered(location: nil, phoneRegion: .unitedStates))
		#expect(!WeatherRadar.isOffered(location: nil, phoneRegion: .canada))
	}
}
