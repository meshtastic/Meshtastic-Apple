import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How far a rendered snapshot may drift from its reference.
///
/// The limit is per tile, not a fraction of the whole image, so a one-character
/// text change fails the same way on a small badge and on a tall docs screenshot.
/// These numbers have not been measured on CI yet; see docs/developer/testing.md.
struct SnapshotPixelTolerance: Equatable {
	/// Largest allowed difference in any RGBA channel (0–255) before a pixel counts as changed.
	/// This absorbs antialiasing and color-conversion noise.
	var perChannel: UInt8
	/// Width and height of the square tiles the image is split into.
	var tileSize: Int
	/// Largest allowed number of changed pixels inside any one tile.
	var maxDifferingPixelsPerTile: Int

	static let standard = SnapshotPixelTolerance(perChannel: 8, tileSize: 32, maxDifferingPixelsPerTile: 16)
}

struct SnapshotPixelComparison: Equatable {
	let differingPixelCount: Int
	let totalPixelCount: Int
	let maxChannelDelta: UInt8
	/// Changed pixels in the worst tile.
	let maxDifferingPixelsInTile: Int
	/// Top-left pixel of the worst tile.
	let worstTileOrigin: SnapshotPixelPoint

	var differingFraction: Double {
		totalPixelCount == 0 ? 0 : Double(differingPixelCount) / Double(totalPixelCount)
	}

	func passes(_ tolerance: SnapshotPixelTolerance) -> Bool {
		maxDifferingPixelsInTile <= tolerance.maxDifferingPixelsPerTile
	}
}

struct SnapshotPixelPoint: Equatable {
	let x: Int
	let y: Int
}

/// An image decoded into 8-bit sRGB RGBA with premultiplied alpha, so PNGs written
/// by different toolchains or in different color spaces compare in one format.
struct SnapshotBitmap: Equatable {
	let width: Int
	let height: Int
	let pixels: [UInt8]

	var dimensions: SnapshotPixelDimensions {
		SnapshotPixelDimensions(width: width, height: height)
	}

	init(width: Int, height: Int, pixels: [UInt8]) {
		precondition(pixels.count == width * height * 4, "RGBA buffer size does not match dimensions")
		self.width = width
		self.height = height
		self.pixels = pixels
	}

	init?(pngData: Data) {
		guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
			  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
			return nil
		}
		self.init(cgImage: image)
	}

	init?(cgImage: CGImage) {
		let width = cgImage.width
		let height = cgImage.height
		guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
			return nil
		}
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(
				data: buffer.baseAddress,
				width: width,
				height: height,
				bitsPerComponent: 8,
				bytesPerRow: width * 4,
				space: colorSpace,
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			) else {
				return false
			}
			context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
			return true
		}
		guard drawn else {
			return nil
		}
		self.init(width: width, height: height, pixels: pixels)
	}

	/// Compares two bitmaps of the same size. A pixel counts as changed when any
	/// channel differs by more than `tolerance.perChannel`. Changed pixels are also
	/// counted per `tolerance.tileSize` tile.
	static func compare(reference: SnapshotBitmap, actual: SnapshotBitmap, tolerance: SnapshotPixelTolerance) -> SnapshotPixelComparison {
		precondition(reference.dimensions == actual.dimensions, "Compare only bitmaps of the same size")
		precondition(tolerance.tileSize > 0, "Tile size must be positive")
		let tileSize = tolerance.tileSize
		let tilesAcross = (reference.width + tileSize - 1) / tileSize
		let tilesDown = (reference.height + tileSize - 1) / tileSize
		var tileCounts = [Int](repeating: 0, count: tilesAcross * tilesDown)
		var differing = 0
		var maxDelta: UInt8 = 0
		reference.pixels.withUnsafeBufferPointer { ref in
			actual.pixels.withUnsafeBufferPointer { act in
				for y in 0..<reference.height {
					let tileRow = (y / tileSize) * tilesAcross
					for x in 0..<reference.width {
						let delta = maxChannelDelta(ref, act, at: (y * reference.width + x) * 4)
						if delta > maxDelta {
							maxDelta = delta
						}
						if delta > tolerance.perChannel {
							differing += 1
							tileCounts[tileRow + x / tileSize] += 1
						}
					}
				}
			}
		}
		var worstTile = 0
		for (index, count) in tileCounts.enumerated() where count > tileCounts[worstTile] {
			worstTile = index
		}
		return SnapshotPixelComparison(
			differingPixelCount: differing,
			totalPixelCount: reference.width * reference.height,
			maxChannelDelta: maxDelta,
			maxDifferingPixelsInTile: tileCounts[worstTile],
			worstTileOrigin: SnapshotPixelPoint(
				x: (worstTile % tilesAcross) * tileSize,
				y: (worstTile / tilesAcross) * tileSize
			)
		)
	}

	/// A faded gray copy of the reference with changed pixels drawn in solid red.
	static func diffImage(reference: SnapshotBitmap, actual: SnapshotBitmap, perChannelTolerance: UInt8) -> SnapshotBitmap {
		precondition(reference.dimensions == actual.dimensions, "Compare only bitmaps of the same size")
		var output = [UInt8](repeating: 255, count: reference.pixels.count)
		reference.pixels.withUnsafeBufferPointer { ref in
			actual.pixels.withUnsafeBufferPointer { act in
				var index = 0
				while index < ref.count {
					if maxChannelDelta(ref, act, at: index) > perChannelTolerance {
						output[index + 1] = 0
						output[index + 2] = 0
					} else {
						let gray = (Int(ref[index]) + Int(ref[index + 1]) + Int(ref[index + 2])) / 3
						let faded = UInt8(255 - (255 - gray) / 4)
						output[index] = faded
						output[index + 1] = faded
						output[index + 2] = faded
					}
					index += 4
				}
			}
		}
		return SnapshotBitmap(width: reference.width, height: reference.height, pixels: output)
	}

	func pngData() -> Data? {
		guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
			  let provider = CGDataProvider(data: Data(pixels) as CFData),
			  let image = CGImage(
				width: width,
				height: height,
				bitsPerComponent: 8,
				bitsPerPixel: 32,
				bytesPerRow: width * 4,
				space: colorSpace,
				bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
				provider: provider,
				decode: nil,
				shouldInterpolate: false,
				intent: .defaultIntent
			  ) else {
			return nil
		}
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
			return nil
		}
		CGImageDestinationAddImage(destination, image, nil)
		guard CGImageDestinationFinalize(destination) else {
			return nil
		}
		return data as Data
	}

	private static func maxChannelDelta(_ lhs: UnsafeBufferPointer<UInt8>, _ rhs: UnsafeBufferPointer<UInt8>, at index: Int) -> UInt8 {
		var result: UInt8 = 0
		for channel in index..<(index + 4) {
			let a = lhs[channel]
			let b = rhs[channel]
			let delta = a > b ? a - b : b - a
			if delta > result {
				result = delta
			}
		}
		return result
	}
}
