import Foundation
import Testing
import UIKit

@Suite("Snapshot pixel comparison")
struct SnapshotPixelComparisonTests {

	@Test("Identical images pass")
	func identicalImagesPass() throws {
		let reference = solidBitmap(width: 20, height: 20, rgba: [40, 120, 200, 255])
		try withReference(reference) { store, referenceURL in
			try store.check(
				pngData: try #require(reference.pngData()),
				pixelDimensions: reference.dimensions,
				referenceURL: referenceURL,
				mode: .verify
			)
		}
		let comparison = SnapshotBitmap.compare(reference: reference, actual: reference, tolerance: .standard)
		#expect(comparison.differingPixelCount == 0)
		#expect(comparison.maxChannelDelta == 0)
		#expect(comparison.maxDifferingPixelsInTile == 0)
	}

	@Test("A few slightly different pixels pass")
	func slightlyDifferentPixelsPass() throws {
		let reference = solidBitmap(width: 20, height: 20, rgba: [40, 120, 200, 255])
		var actual = reference
		for (x, y) in [(0, 0), (5, 7), (19, 19)] {
			actual = actual.settingPixel(x: x, y: y, rgba: [43, 118, 204, 255])
		}
		// One pixel well past the channel tolerance stays under the per-tile limit.
		actual = actual.settingPixel(x: 10, y: 10, rgba: [255, 0, 0, 255])

		let comparison = SnapshotBitmap.compare(reference: reference, actual: actual, tolerance: .standard)
		#expect(comparison.differingPixelCount == 1)
		#expect(comparison.maxChannelDelta == 215)
		#expect(comparison.passes(.standard))

		try withReference(reference) { store, referenceURL in
			try store.check(
				pngData: try #require(actual.pngData()),
				pixelDimensions: actual.dimensions,
				referenceURL: referenceURL,
				mode: .verify
			)
		}
	}

	@Test("Noise spread across many tiles passes")
	func spreadNoisePasses() {
		let reference = solidBitmap(width: 320, height: 320, rgba: [255, 255, 255, 255])
		var actual = reference
		// Two changed pixels in each of the 100 tiles: 200 in total.
		for tileY in 0..<10 {
			for tileX in 0..<10 {
				actual = actual.settingPixel(x: tileX * 32 + 3, y: tileY * 32 + 3, rgba: [0, 0, 0, 255])
				actual = actual.settingPixel(x: tileX * 32 + 20, y: tileY * 32 + 9, rgba: [0, 0, 0, 255])
			}
		}
		let comparison = SnapshotBitmap.compare(reference: reference, actual: actual, tolerance: .standard)
		#expect(comparison.differingPixelCount == 200)
		#expect(comparison.maxDifferingPixelsInTile == 2)
		#expect(comparison.passes(.standard))
	}

	@Test("A changed block fails and carries actual and diff images")
	func changedBlockFails() throws {
		let reference = solidBitmap(width: 40, height: 40, rgba: [40, 120, 200, 255])
		var actual = reference
		for y in 34..<39 {
			for x in 34..<39 {
				actual = actual.settingPixel(x: x, y: y, rgba: [40, 160, 200, 255])
			}
		}

		try withReference(reference) { store, referenceURL in
			do {
				try store.check(
					pngData: try #require(actual.pngData()),
					pixelDimensions: actual.dimensions,
					referenceURL: referenceURL,
					mode: .verify
				)
				Issue.record("Verification unexpectedly accepted a changed block")
			} catch let SnapshotReferenceError.pixelMismatch(comparison, tolerance, images) {
				#expect(comparison.differingPixelCount == 25)
				#expect(comparison.totalPixelCount == 1600)
				#expect(comparison.maxChannelDelta == 40)
				#expect(comparison.maxDifferingPixelsInTile == 25)
				#expect(comparison.worstTileOrigin == SnapshotPixelPoint(x: 32, y: 32))
				#expect(tolerance == store.tolerance)
				let diffPNG = try #require(images.diffPNG)
				let diff = try #require(SnapshotBitmap(pngData: diffPNG))
				#expect(diff.pixel(x: 35, y: 35) == [255, 0, 0, 255])
				#expect(diff.pixel(x: 0, y: 0) != [255, 0, 0, 255])
				#expect(SnapshotBitmap(pngData: images.actualPNG) == actual)
			}
		}
	}

	@Test("The pixel check is skipped when turned off")
	func pixelCheckCanBeTurnedOff() throws {
		let reference = solidBitmap(width: 20, height: 20, rgba: [40, 120, 200, 255])
		let actual = solidBitmap(width: 20, height: 20, rgba: [200, 40, 40, 255])
		let pngData = try #require(actual.pngData())

		try withReference(reference) { store, referenceURL in
			try store.check(
				pngData: pngData,
				pixelDimensions: actual.dimensions,
				referenceURL: referenceURL,
				mode: .verify,
				comparePixels: false
			)
			var disabled = store
			disabled.comparesPixels = false
			try disabled.check(pngData: pngData, pixelDimensions: actual.dimensions, referenceURL: referenceURL, mode: .verify)
		}
	}

	@Test("The pixel check needs an explicit environment value")
	func pixelCheckRequiresEnvironmentValue() {
		#expect(!SnapshotPixelCheck.isEnabled(environment: [:]))
		#expect(!SnapshotPixelCheck.isEnabled(environment: ["MESHTASTIC_COMPARE_SNAPSHOT_PIXELS": "0"]))
		#expect(SnapshotPixelCheck.isEnabled(environment: ["MESHTASTIC_COMPARE_SNAPSHOT_PIXELS": "1"]))
		#expect(SnapshotPixelCheck.isEnabled(environment: ["TEST_RUNNER_MESHTASTIC_COMPARE_SNAPSHOT_PIXELS": "1"]))
	}

	@Test("Different sizes fail before pixels are compared")
	func differentSizeFails() throws {
		let reference = solidBitmap(width: 20, height: 20, rgba: [40, 120, 200, 255])
		let actual = solidBitmap(width: 20, height: 21, rgba: [40, 120, 200, 255])

		try withReference(reference) { store, referenceURL in
			#expect(throws: SnapshotReferenceError.dimensionMismatch(
				reference: SnapshotPixelDimensions(width: 20, height: 20),
				actual: SnapshotPixelDimensions(width: 20, height: 21)
			)) {
				try store.check(
					pngData: try #require(actual.pngData()),
					pixelDimensions: actual.dimensions,
					referenceURL: referenceURL,
					mode: .verify
				)
			}
		}
	}

	@Test("A changed text label fails at the default tolerance", arguments: [44.0, 1124.0])
	func changedTextLabelFails(canvasHeight: Double) throws {
		let reference = try #require(SnapshotBitmap(cgImage: textImage("Channel 1", height: canvasHeight)))
		let actual = try #require(SnapshotBitmap(cgImage: textImage("Channel 2", height: canvasHeight)))
		let comparison = SnapshotBitmap.compare(reference: reference, actual: actual, tolerance: .standard)
		#expect(comparison.differingFraction < 0.01)
		#expect(!comparison.passes(.standard))
	}

	@Test("Display P3 and sRGB encodings of the same color compare equal")
	func colorSpacesAreNormalized() throws {
		let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
		let color = try #require(CGColor(colorSpace: srgb, components: [0.2, 0.5, 0.8, 1]))
		let reference = try #require(SnapshotBitmap(cgImage: filledImage(color: color, space: srgb)))
		let actual = try #require(SnapshotBitmap(cgImage: filledImage(color: color, space: p3)))
		let tolerance = SnapshotPixelTolerance(perChannel: 1, tileSize: 32, maxDifferingPixelsPerTile: 0)
		let comparison = SnapshotBitmap.compare(reference: reference, actual: actual, tolerance: tolerance)
		#expect(comparison.differingPixelCount == 0)
	}

	// MARK: - Helpers

	private func withReference(
		_ reference: SnapshotBitmap,
		_ body: (SnapshotReferenceStore, URL) throws -> Void
	) throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let referenceURL = directory.appendingPathComponent("reference.png")
		try #require(reference.pngData()).write(to: referenceURL)

		var store = SnapshotReferenceStore()
		store.comparesPixels = true
		try body(store, referenceURL)
	}

	private func solidBitmap(width: Int, height: Int, rgba: [UInt8]) -> SnapshotBitmap {
		SnapshotBitmap(width: width, height: height, pixels: Array((0..<(width * height)).map { _ in rgba }.joined()))
	}

	private func textImage(_ text: String, height: Double) throws -> CGImage {
		let format = UIGraphicsImageRendererFormat()
		format.scale = 3
		format.opaque = true
		let size = CGSize(width: 390, height: height)
		let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
			UIColor.white.setFill()
			UIRectFill(CGRect(origin: .zero, size: size))
			(text as NSString).draw(
				at: CGPoint(x: 16, y: 12),
				withAttributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.black]
			)
		}
		return try #require(image.cgImage)
	}

	private func filledImage(color: CGColor, space: CGColorSpace) throws -> CGImage {
		let context = try #require(CGContext(
			data: nil,
			width: 4,
			height: 4,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: space,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))
		context.setFillColor(color)
		context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
		return try #require(context.makeImage())
	}
}

private extension SnapshotBitmap {
	func pixel(x: Int, y: Int) -> [UInt8] {
		let index = (y * width + x) * 4
		return Array(pixels[index..<(index + 4)])
	}

	func settingPixel(x: Int, y: Int, rgba: [UInt8]) -> SnapshotBitmap {
		var copy = pixels
		let index = (y * width + x) * 4
		copy.replaceSubrange(index..<(index + 4), with: rgba)
		return SnapshotBitmap(width: width, height: height, pixels: copy)
	}
}
