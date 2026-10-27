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

	// MARK: Smoothing

	@Test func cellGridCountsKilometerCellsAndPadsEachSide() throws {
		// A zoom 10 tile is about 39 km of Mercator across.
		let bounds = WeatherRadarTileOverlay.mercatorBounds(x: 200, y: 360, z: 10)
		let grid = try #require(WeatherRadarCellGrid(bounds: bounds, outputWidth: 512, outputHeight: 512))
		#expect(grid.columns == Int((bounds.width / WeatherRadarCellGrid.cellMeters).rounded()))
		// Cells are taller than wide in Mercator away from the equator.
		#expect(grid.rows < grid.columns)
		let padding = WeatherRadarCellGrid.padding
		#expect(grid.requestWidth == grid.columns + 2 * padding && grid.requestHeight == grid.rows + 2 * padding)
		#expect(abs(grid.paddedBounds.width - bounds.width * Double(grid.requestWidth) / Double(grid.columns)) < 1e-6)
		#expect(abs(grid.paddedBounds.midX - bounds.midX) < 1e-6 && abs(grid.paddedBounds.midY - bounds.midY) < 1e-6)
	}

	@Test func noCellGridWhenAPixelCoversACell() {
		let bounds = WeatherRadarTileOverlay.mercatorBounds(x: 10, y: 22, z: 6)
		#expect(WeatherRadarCellGrid(bounds: bounds, outputWidth: 512, outputHeight: 512) == nil)
	}

	/// Rain cells in the middle of the padded grid, smoothed to a 512 pixel tile.
	private func smoothed(cells: [(Int, Int)], grid: WeatherRadarCellGrid) throws -> (image: CGImage, alphas: [UInt8]) {
		let width = grid.requestWidth, height = grid.requestHeight
		var bytes = [UInt8](repeating: 0, count: width * height * 4)
		for (dx, dy) in cells {
			let index = ((height / 2 + dy) * width + width / 2 + dx) * 4
			bytes[index] = 40; bytes[index + 1] = 200; bytes[index + 2] = 80; bytes[index + 3] = 255
		}
		let input = try #require(bytes.withUnsafeMutableBytes { buffer in
			CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
					  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
		})
		let output = try #require(WeatherRadarSmoothing.smooth(input, grid: grid, width: 512, height: 512))
		let pixels = try #require(output.dataProvider?.data as Data?)
		return (output, stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] })
	}

	@Test func smoothingRoundsAShowerAndDropsALoneCell() throws {
		let bounds = WeatherRadarTileOverlay.mercatorBounds(x: 200, y: 360, z: 10)
		let grid = try #require(WeatherRadarCellGrid(bounds: bounds, outputWidth: 512, outputHeight: 512))
		let block = (-1...1).flatMap { dx in (-1...1).map { dy in (dx, dy) } }
		let shower = try smoothed(cells: block, grid: grid)
		#expect(shower.image.width == 512 && shower.image.height == 512)
		let covered = shower.alphas.filter { $0 > 0 }.count
		// A 3 by 3 block of cells comes out round: solid in the middle, its square corners cut off.
		let cellWidth = 512.0 / Double(grid.columns), cellHeight = 512.0 / Double(grid.rows)
		let padding = Double(WeatherRadarCellGrid.padding)
		let centerX = (Double(grid.requestWidth / 2) + 0.5 - padding) * cellWidth
		let centerY = (Double(grid.requestHeight / 2) + 0.5 - padding) * cellHeight
		let alpha = { (x: Double, y: Double) in shower.alphas[Int(y) * 512 + Int(x)] }
		#expect(alpha(centerX, centerY) == 255)
		for (dx, dy) in [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)] {
			#expect(alpha(centerX + dx * 1.45 * cellWidth, centerY + dy * 1.45 * cellHeight) == 0)
		}
		// Its edge is a thin line, not a long fade.
		#expect(shower.alphas.filter { $0 > 0 && $0 < 255 }.count < covered / 2)
		// One cell on its own is speckle and is softened away.
		#expect(try smoothed(cells: [(0, 0)], grid: grid).alphas.allSatisfy { $0 == 0 })
	}

	/// A premultiplied RGBA image of the columns `from..<(from + width)` of `field`, which holds
	/// `fieldWidth` by `height` cells.
	private func image(_ field: [UInt8], fieldWidth: Int, height: Int, from: Int, width: Int) throws -> CGImage {
		var bytes = [UInt8](repeating: 0, count: width * height * 4)
		for row in 0..<height {
			let source = (row * fieldWidth + from) * 4
			bytes.replaceSubrange((row * width * 4)..<((row + 1) * width * 4), with: field[source..<(source + width * 4)])
		}
		return try #require(bytes.withUnsafeMutableBytes { buffer in
			CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
					  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
		})
	}

	private func alphas(_ image: CGImage) throws -> [UInt8] {
		let pixels = try #require(image.dataProvider?.data as Data?)
		return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
	}

	@Test func neighboringTilesMeetWithoutASeam() throws {
		// Two tiles side by side at the equator, where cells are square, and the box covering both.
		let columns = 12, rows = 12, scale = 16
		let cell = WeatherRadarCellGrid.cellMeters
		let left = CGRect(x: 0, y: -Double(rows) * cell / 2, width: Double(columns) * cell, height: Double(rows) * cell)
		let right = left.offsetBy(dx: left.width, dy: 0)
		let leftGrid = try #require(WeatherRadarCellGrid(bounds: left, outputWidth: columns * scale, outputHeight: rows * scale))
		let rightGrid = try #require(WeatherRadarCellGrid(bounds: right, outputWidth: columns * scale, outputHeight: rows * scale))
		let bothGrid = try #require(WeatherRadarCellGrid(bounds: left.union(right), outputWidth: 2 * columns * scale, outputHeight: rows * scale))
		#expect(leftGrid.columns == columns && bothGrid.columns == 2 * columns)
		// Rain in the cells around the shared edge, so it crosses from one tile into the other.
		let fieldWidth = bothGrid.requestWidth, height = bothGrid.requestHeight
		var field = [UInt8](repeating: 0, count: fieldWidth * height * 4)
		var random = SystemRandomNumberGenerator()
		let edge = WeatherRadarCellGrid.padding + columns
		for row in 0..<height {
			for column in (edge - 6)..<(edge + 6) where Bool.random(using: &random) {
				let index = (row * fieldWidth + column) * 4
				field[index] = 40; field[index + 1] = 200; field[index + 2] = 80; field[index + 3] = 255
			}
		}
		let tileWidth = columns * scale, tileHeight = rows * scale
		let leftTile = try alphas(try #require(WeatherRadarSmoothing.smooth(
			try image(field, fieldWidth: fieldWidth, height: height, from: 0, width: leftGrid.requestWidth),
			grid: leftGrid, width: tileWidth, height: tileHeight)))
		let rightTile = try alphas(try #require(WeatherRadarSmoothing.smooth(
			try image(field, fieldWidth: fieldWidth, height: height, from: columns, width: rightGrid.requestWidth),
			grid: rightGrid, width: tileWidth, height: tileHeight)))
		let both = try alphas(try #require(WeatherRadarSmoothing.smooth(
			try image(field, fieldWidth: fieldWidth, height: height, from: 0, width: fieldWidth),
			grid: bothGrid, width: 2 * tileWidth, height: tileHeight)))
		var largest = 0
		for y in 0..<tileHeight {
			for x in 0..<tileWidth {
				largest = max(largest, abs(Int(leftTile[y * tileWidth + x]) - Int(both[y * 2 * tileWidth + x])))
				largest = max(largest, abs(Int(rightTile[y * tileWidth + x]) - Int(both[y * 2 * tileWidth + tileWidth + x])))
			}
		}
		// Rounding to 8 bits can differ by one; a seam differs by far more.
		#expect(largest <= 1)
		#expect(both.contains(255))
	}

	@Test func edgeKeepsFullRainAndDropsTheFade() {
		#expect(WeatherRadarSmoothing.edgeAlpha(1) == 1)
		#expect(WeatherRadarSmoothing.edgeAlpha(0.3) == 0)
		#expect(abs(WeatherRadarSmoothing.edgeAlpha(0.5) - 0.5) < 1e-6)
	}

	// MARK: Close in

	@Test func overlayDrawsPastTheZoomItFetches() {
		let overlay = WeatherRadarTileOverlay(refreshPeriod: 1)
		#expect(overlay.maximumZ > WeatherRadarTileOverlay.fetchMaximumZ)
	}

	@Test func closeTileIsAPartOfItsZoomTwelveTile() {
		// Zoom 14 is two levels in: a quarter of the zoom 12 tile across, here the third column and
		// the second row of four.
		let part = WeatherRadarTilePart(x: 4 * 655 + 2, y: 4 * 1430 + 1, z: 14, fetchZ: 12)
		#expect(part.ancestorX == 655 && part.ancestorY == 1430 && part.ancestorZ == 12)
		#expect(part.rect == CGRect(x: 0.5, y: 0.25, width: 0.25, height: 0.25))
		// At the fetch zoom or above, the tile is its own ancestor.
		let same = WeatherRadarTilePart(x: 655, y: 1430, z: 12, fetchZ: 12)
		#expect(same.ancestorX == 655 && same.ancestorZ == 12 && same.rect == CGRect(x: 0, y: 0, width: 1, height: 1))
	}

	@Test func cutTakesTheTilesQuarter() throws {
		// A 256 pixel tile, red in the top left quarter and blue in the bottom right, clear elsewhere.
		let size = 256
		var bytes = [UInt8](repeating: 0, count: size * size * 4)
		for y in 0..<size {
			for x in 0..<size {
				let index = (y * size + x) * 4
				if x < 128, y < 128 { bytes[index] = 255; bytes[index + 3] = 255 }
				if x >= 128, y >= 128 { bytes[index + 2] = 255; bytes[index + 3] = 255 }
			}
		}
		let image = try #require(bytes.withUnsafeMutableBytes { buffer in
			CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
					  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
		})
		func center(_ part: WeatherRadarTilePart) throws -> [UInt8] {
			let cut = try #require(part.cut(from: image, size: 512))
			#expect(cut.width == 512 && cut.height == 512)
			let pixels = try #require(cut.dataProvider?.data as Data?)
			let index = 256 * cut.bytesPerRow + 256 * 4
			return Array(pixels[index..<(index + 4)])
		}
		#expect(try center(WeatherRadarTilePart(x: 0, y: 0, z: 13, fetchZ: 12)) == [255, 0, 0, 255])
		#expect(try center(WeatherRadarTilePart(x: 1, y: 1, z: 13, fetchZ: 12)) == [0, 0, 255, 255])
		#expect(try center(WeatherRadarTilePart(x: 1, y: 0, z: 13, fetchZ: 12))[3] == 0)
	}
}
