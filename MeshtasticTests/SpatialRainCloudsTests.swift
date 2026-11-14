//
//  SpatialRainCloudsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//
import CoreGraphics
import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

@Suite("Spatial rain clouds")
struct SpatialRainCloudsTests {
	/// A square image, clear but for a solid block of `color` in the middle.
	private func image(size: Int = 64, block: Int = 16, color: CGColor = CGColor(red: 0, green: 0.8, blue: 0, alpha: 1)) -> CGImage {
		let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
								space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		context.setFillColor(color)
		let start = (size - block) / 2
		context.fill(CGRect(x: start, y: start, width: block, height: block))
		return context.makeImage()!
	}

	/// RGBA of each pixel, top row first.
	private func pixels(_ image: CGImage) -> [UInt8] {
		var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
		let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
								space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
		return data
	}

	private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
		pixels(image)[(y * image.width + x) * 4 + 3]
	}

	// MARK: Height

	@Test func sheetsFloatJustOverTheGround() {
		#expect(SpatialTerrainGeometry.cloudLift > SpatialTerrainGeometry.overlayLift, "over the coverage")
		#expect(SpatialTerrainGeometry.cloudLift + SpatialRainClouds.layers.last!.rise < 0.03, "a little over the ground, not up at the pins' heads")
	}

	// MARK: Images

	@Test func stackedSheetsComeToTheMapsStrength() {
		#expect(abs(SpatialRainClouds.combinedOpacity - Float(WeatherRadar.opacity)) < 0.03)
		#expect(SpatialRainClouds.layers.first?.blur == 0, "the bottom sheet is the sharp rain")
		#expect(zip(SpatialRainClouds.layers, SpatialRainClouds.layers.dropFirst()).allSatisfy { $1.rise > $0.rise && $1.blur > $0.blur })
	}

	@Test func softenedKeepsTheSizeAndSpreadsTheRain() throws {
		let source = image()
		let soft = try #require(SpatialRainClouds.softened(source, blur: 0.05))
		#expect(soft.width == source.width && soft.height == source.height)
		// Just outside the block: clear in the source, some rain once softened.
		#expect(alpha(source, x: 22, y: 32) == 0)
		#expect(alpha(soft, x: 22, y: 32) > 0)
		#expect(alpha(soft, x: 32, y: 32) < 255, "the middle thins as it spreads")
	}

	@Test func softenedEmptyImageStaysEmpty() throws {
		let soft = try #require(SpatialRainClouds.softened(image(block: 0), blur: 0.05))
		#expect(pixels(soft).allSatisfy { $0 == 0 })
	}

	@Test func shadowIsBlackWhereTheRainIs() throws {
		let shadow = try #require(SpatialRainClouds.shadow(image()))
		let data = pixels(shadow)
		let middle = (32 * shadow.width + 32) * 4
		#expect(data[middle + 3] > 0)
		#expect(data[middle] == 0 && data[middle + 1] == 0 && data[middle + 2] == 0)
		#expect(alpha(shadow, x: 0, y: 0) == 0)
	}

	@Test func fadedScalesEachPixelByItsPlace() throws {
		let source = image(size: 8, block: 8, color: CGColor(red: 0, green: 1, blue: 0, alpha: 1))
		// Full strength on the left half, none on the right.
		let faded = try #require(SpatialRainClouds.faded(source) { u, _ in u < 0.5 ? 1 : 0 })
		#expect(alpha(faded, x: 1, y: 4) == 255)
		#expect(alpha(faded, x: 6, y: 4) == 0)
		let data = pixels(faded)
		#expect(data[(4 * 8 + 6) * 4 + 1] == 0, "premultiplied: the color goes with the alpha")
	}
}
