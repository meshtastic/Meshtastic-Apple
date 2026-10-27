//
//  SpatialWeatherRadarTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
import CoreGraphics
import CoreLocation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Meshtastic

@Suite("Spatial map weather radar")
struct SpatialWeatherRadarTests {
	let box = GeoBounds(minLon: -122.40, minLat: 47.55, maxLon: -122.30, maxLat: 47.65)
	let seattle = CLLocationCoordinate2D(latitude: 47.61, longitude: -122.33)

	// MARK: Request

	@Test func requestAsksForTheBoxsCellsToDrawSmoothAtTheDrapeSize() throws {
		let frame = SpatialFrame(bounds: box)
		let plan = SpatialWeatherRadar.plan(for: frame, refreshPeriod: 42)
		let query = try query(plan.request)
		#expect(max(plan.size.width, plan.size.height) == 1024)
		let grid = try #require(plan.grid)
		// 0.1° of longitude is about ten 1 km cells, plus the padding on each side.
		let padding = WeatherRadarCellGrid.padding
		#expect(grid.columns == 10 && query["WIDTH"] == String(10 + 2 * padding) && query["HEIGHT"] == String(grid.rows + 2 * padding))
		let padded = grid.paddedBounds
		#expect(query["BBOX"] == [padded.minX, padded.minY, padded.maxX, padded.maxY].map { String(format: "%.2f", $0) }.joined(separator: ","))
		#expect(query["LAYERS"] == "conus_bref_qcd" && query["period"] == "42")
		#expect(plan.request.timeoutInterval == 15)
	}

	@Test func aTableWiderThanTheDrapeAsksForTheDrapeSize() throws {
		let wide = GeoBounds(minLon: -125, minLat: 40, maxLon: -110, maxLat: 49)
		let plan = SpatialWeatherRadar.plan(for: SpatialFrame(bounds: wide), refreshPeriod: 1)
		#expect(plan.grid == nil)
		let query = try query(plan.request)
		#expect(query["WIDTH"] == String(Int(plan.size.width)) && query["HEIGHT"] == String(Int(plan.size.height)))
	}

	/// The server draws the bounds edge to edge, linear in Mercator meters, so a coordinate lands
	/// in its image where the terrain's texture puts it.
	@Test func imageLinesUpWithTheTerrainTexture() {
		let frame = SpatialFrame(bounds: box)
		let bounds = WeatherRadar.mercatorBounds(for: box)
		let size = CGSize(width: 1024, height: 1024)
		let northWest = CLLocationCoordinate2D(latitude: box.maxLat, longitude: box.minLon)
		let southEast = CLLocationCoordinate2D(latitude: box.minLat, longitude: box.maxLon)
		for coordinate in [seattle, northWest, southEast, CLLocationCoordinate2D(latitude: 47.56, longitude: -122.31)] {
			let canvas = SpatialTextureRenderer.canvasPoint(coordinate, frame: frame, size: size)
			// The textbook Web Mercator projection, y up like the canvas.
			let radius = 6_378_137.0
			let x = radius * coordinate.longitude * .pi / 180
			let y = radius * log(tan(.pi / 4 + coordinate.latitude * .pi / 360))
			let image = CGPoint(x: (x - bounds.minX) / bounds.width * size.width, y: (y - bounds.minY) / bounds.height * size.height)
			#expect(abs(image.x - canvas.x) < 1e-3 && abs(image.y - canvas.y) < 1e-3)
		}
	}

	// MARK: Gate and key

	@Test func fetchesOnlyWhenShownOfferedOnlineAndInCoverage() {
		let honolulu = CLLocationCoordinate2D(latitude: 21.31, longitude: -157.86)
		#expect(SpatialWeatherRadar.shouldFetch(show: true, offered: true, networkAvailable: true, center: seattle))
		#expect(!SpatialWeatherRadar.shouldFetch(show: false, offered: true, networkAvailable: true, center: seattle))
		#expect(!SpatialWeatherRadar.shouldFetch(show: true, offered: false, networkAvailable: true, center: seattle))
		#expect(!SpatialWeatherRadar.shouldFetch(show: true, offered: true, networkAvailable: false, center: seattle))
		// The device is in the lower 48; the table is not.
		#expect(!SpatialWeatherRadar.shouldFetch(show: true, offered: true, networkAvailable: true, center: honolulu))
	}

	@Test func keyChangesWithTheTerrainThePeriodAndTheGate() {
		let key = SpatialWeatherRadar.key(revision: 3, refreshPeriod: 100, fetch: true)
		#expect(key == SpatialWeatherRadar.key(revision: 3, refreshPeriod: 100, fetch: true))
		#expect(key != SpatialWeatherRadar.key(revision: 4, refreshPeriod: 100, fetch: true))
		#expect(key != SpatialWeatherRadar.key(revision: 3, refreshPeriod: 101, fetch: true))
		#expect(key != SpatialWeatherRadar.key(revision: 3, refreshPeriod: 100, fetch: false))
		// Five minutes on is the next period, so the next key; the same minute is not.
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		let period = WeatherRadar.refreshPeriod(at: now)
		#expect(SpatialWeatherRadar.key(revision: 3, refreshPeriod: WeatherRadar.refreshPeriod(at: now.addingTimeInterval(60)), fetch: true)
			== SpatialWeatherRadar.key(revision: 3, refreshPeriod: period, fetch: true))
		#expect(SpatialWeatherRadar.key(revision: 3, refreshPeriod: WeatherRadar.refreshPeriod(at: now.addingTimeInterval(WeatherRadar.refreshInterval)), fetch: true)
			!= SpatialWeatherRadar.key(revision: 3, refreshPeriod: period, fetch: true))
	}

	// MARK: Cache

	@Test func cacheServesTheSameBoxAndPeriodAndKeepsTheLastImageWhenAFetchFails() throws {
		let image = try #require(blank(width: 2, height: 2))
		let cache = SpatialWeatherRadarCache(bounds: box, refreshPeriod: 100, image: image)
		#expect(cache.current(bounds: box, refreshPeriod: 100) === image)
		// A new period fetches again...
		#expect(cache.current(bounds: box, refreshPeriod: 101) == nil)
		// ...and if that fetch fails, the last image stays up for the same box, for one period.
		#expect(cache.fallback(bounds: box, refreshPeriod: 100) === image)
		#expect(cache.fallback(bounds: box, refreshPeriod: 101) === image)
		// Two periods on it is too old: the drape clears rather than show it.
		#expect(cache.fallback(bounds: box, refreshPeriod: 102) == nil)
		// Rain from another box is never draped.
		let elsewhere = GeoBounds(minLon: -122.5, minLat: 47.5, maxLon: -122.2, maxLat: 47.8)
		#expect(cache.current(bounds: elsewhere, refreshPeriod: 100) == nil)
		#expect(cache.fallback(bounds: elsewhere, refreshPeriod: 101) == nil)
	}

	@Test func aFailedFetchKeepsTheLastImageOrRetriesOnceThenClears() throws {
		let image = try #require(blank(width: 2, height: 2))
		let cache = SpatialWeatherRadarCache(bounds: box, refreshPeriod: 100, image: image)
		// The last image is a period old at most: it stays up, no retry.
		#expect(SpatialWeatherRadar.afterFailedFetch(cache: cache, bounds: box, refreshPeriod: 101, retried: false) == .keep(image))
		#expect(SpatialWeatherRadar.afterFailedFetch(cache: cache, bounds: box, refreshPeriod: 101, retried: true) == .keep(image))
		// Nothing to keep: the first failure tries again soon rather than wait for the next period...
		#expect(SpatialWeatherRadar.afterFailedFetch(cache: nil, bounds: box, refreshPeriod: 101, retried: false) == .retry)
		#expect(SpatialWeatherRadar.afterFailedFetch(cache: cache, bounds: box, refreshPeriod: 102, retried: false) == .retry)
		// ...and a second failure clears the drape until the next period.
		#expect(SpatialWeatherRadar.afterFailedFetch(cache: nil, bounds: box, refreshPeriod: 101, retried: true) == .clear)
		#expect(SpatialWeatherRadar.afterFailedFetch(cache: cache, bounds: box, refreshPeriod: 102, retried: true) == .clear)
		#expect(SpatialWeatherRadar.retryDelay == 30)
	}

	// MARK: Decode

	@Test func decodesIntoPremultipliedRGBAAtTheSameSize() throws {
		let data = try #require(png(width: 4, height: 3) { context in
			// One half-see-through red pixel in the top-left corner; the rest clear.
			context.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
			context.fill(CGRect(x: 0, y: 2, width: 1, height: 1))
		})
		let image = try #require(SpatialWeatherRadar.decode(data))
		#expect(image.width == 4 && image.height == 3)
		#expect(image.alphaInfo == .premultipliedLast)
		#expect(image.bitsPerPixel == 32)
		let red = pixel(image, x: 0, y: 0)
		#expect(abs(red.x - 128) <= 2 && red.y == 0 && red.z == 0 && abs(red.w - 128) <= 2)
		#expect(pixel(image, x: 3, y: 2).w == 0)
	}

	@Test func decodeTurnsDownWhatIsNotAnImage() {
		#expect(SpatialWeatherRadar.decode(Data("<ServiceException>".utf8)) == nil)
		#expect(SpatialWeatherRadar.decode(Data()) == nil)
	}

	// MARK: Helpers

	private func query(_ request: URLRequest) throws -> [String: String] {
		let url = try #require(request.url)
		let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
		return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
	}

	private func blank(width: Int, height: Int) -> CGImage? {
		CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
				  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
	}

	/// A PNG with straight alpha, the way the server's come, drawn by `draw`.
	private func png(width: Int, height: Int, draw: (CGContext) -> Void) -> Data? {
		guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
									  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
		draw(context)
		guard let image = context.makeImage() else { return nil }
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
		CGImageDestinationAddImage(destination, image, nil)
		guard CGImageDestinationFinalize(destination) else { return nil }
		return data as Data
	}

	/// RGBA bytes of a pixel, rows counted from the top of the image.
	private func pixel(_ image: CGImage, x: Int, y: Int) -> SIMD4<Int> {
		var bytes = [UInt8](repeating: 0, count: 4)
		let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
								space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
		return SIMD4(Int(bytes[0]), Int(bytes[1]), Int(bytes[2]), Int(bytes[3]))
	}
}
