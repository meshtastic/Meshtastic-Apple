import Foundation
import UIKit

struct SnapshotPixelDimensions: Equatable {
	let width: Int
	let height: Int
}

enum SnapshotReferenceMode: Equatable {
	case verify
	case record

	static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> SnapshotReferenceMode {
		let variableNames = [
			"MESHTASTIC_RECORD_SNAPSHOTS",
			"TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS"
		]
		return variableNames.contains(where: { environment[$0] == "1" }) ? .record : .verify
	}
}

enum SnapshotReferencePlatform {
	case iOS
	case macCatalyst

	static var current: SnapshotReferencePlatform {
		#if targetEnvironment(macCatalyst)
		.macCatalyst
		#else
		.iOS
		#endif
	}
}

struct SnapshotReferencePath {
	static func referenceURL(
		testFileURL: URL,
		snapshotName: String,
		forDocs: Bool,
		platform: SnapshotReferencePlatform
	) -> URL {
		let baseDirectory: URL
		if forDocs {
			baseDirectory = testFileURL
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.appendingPathComponent("docs")
				.appendingPathComponent("assets")
				.appendingPathComponent("screenshots")
		} else {
			baseDirectory = testFileURL
				.deletingLastPathComponent()
				.appendingPathComponent("__Snapshots__")
				.appendingPathComponent(testFileURL.deletingPathExtension().lastPathComponent)
		}

		let platformDirectory: URL
		switch platform {
		case .iOS:
			platformDirectory = baseDirectory
		case .macCatalyst:
			platformDirectory = baseDirectory.appendingPathComponent("macCatalyst")
		}
		return platformDirectory.appendingPathComponent("\(snapshotName).png")
	}
}

enum SnapshotReferenceError: Error, Equatable, CustomStringConvertible {
	case missingReference(URL)
	case unreadableReference(URL)
	case dimensionMismatch(reference: SnapshotPixelDimensions, actual: SnapshotPixelDimensions)
	case contentMismatch(differingPixels: Int, totalPixels: Int)

	var description: String {
		switch self {
		case let .missingReference(url):
			return "Missing snapshot reference at \(url.path). Run with TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS=1 to record it explicitly."
		case let .unreadableReference(url):
			return "Unable to read snapshot reference at \(url.path)."
		case let .dimensionMismatch(reference, actual):
			return "Snapshot dimensions changed from \(reference.width)×\(reference.height) to \(actual.width)×\(actual.height). Run with TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS=1 to replace the reference explicitly."
		case let .contentMismatch(differingPixels, totalPixels):
			let percentage = Double(differingPixels) / Double(totalPixels) * 100
			return "Snapshot content changed in \(String(format: "%.3f", percentage))% of pixels. Run with TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS=1 to replace the reference explicitly."
		}
	}
}

struct SnapshotReferenceStore {
	private static let channelTolerance: UInt8 = 8
	private static let maximumDifferentPixelRatio = 0.001
	private let fileManager = FileManager.default

	/// Pixel comparison ignores RGBA channel differences of 8 or less and
	/// accepts up to 0.1% differing pixels.
	func check(
		pngData: Data,
		referenceURL: URL,
		mode: SnapshotReferenceMode,
		comparePixels: Bool = false
	) throws {
		if case .record = mode {
			try fileManager.createDirectory(
				at: referenceURL.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try pngData.write(to: referenceURL, options: .atomic)
			return
		}

		guard fileManager.fileExists(atPath: referenceURL.path) else {
			throw SnapshotReferenceError.missingReference(referenceURL)
		}
		guard let referenceData = try? Data(contentsOf: referenceURL),
			  let referenceImage = UIImage(data: referenceData),
			  let referenceCGImage = referenceImage.cgImage,
			  let actualImage = UIImage(data: pngData)?.cgImage else {
			throw SnapshotReferenceError.unreadableReference(referenceURL)
		}

		let referenceDimensions = SnapshotPixelDimensions(
			width: referenceCGImage.width,
			height: referenceCGImage.height
		)
		let actualDimensions = SnapshotPixelDimensions(
			width: actualImage.width,
			height: actualImage.height
		)
		guard referenceDimensions == actualDimensions else {
			throw SnapshotReferenceError.dimensionMismatch(
				reference: referenceDimensions,
				actual: actualDimensions
			)
		}

		guard comparePixels else { return }
		guard let differingPixels = Self.differingPixelCount(
			between: referenceCGImage,
			and: actualImage
		) else {
			throw SnapshotReferenceError.unreadableReference(referenceURL)
		}
		let totalPixels = referenceCGImage.width * referenceCGImage.height
		guard Double(differingPixels) / Double(totalPixels) <= Self.maximumDifferentPixelRatio else {
			throw SnapshotReferenceError.contentMismatch(
				differingPixels: differingPixels,
				totalPixels: totalPixels
			)
		}
	}

	private static func differingPixelCount(
		between reference: CGImage,
		and actual: CGImage
	) -> Int? {
		guard let referenceBytes = rgbaBytes(for: reference),
			  let actualBytes = rgbaBytes(for: actual),
			  referenceBytes.count == actualBytes.count else { return nil }

		var differingPixels = 0
		for offset in stride(from: 0, to: referenceBytes.count, by: 4) {
			let differs = (0..<4).contains { channel in
				abs(Int(referenceBytes[offset + channel]) - Int(actualBytes[offset + channel])) > channelTolerance
			}
			if differs {
				differingPixels += 1
			}
		}
		return differingPixels
	}

	private static func rgbaBytes(for image: CGImage) -> [UInt8]? {
		let bytesPerRow = image.width * 4
		var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
			CGBitmapInfo.byteOrder32Big.rawValue
		let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(
				data: buffer.baseAddress,
				width: image.width,
				height: image.height,
				bitsPerComponent: 8,
				bytesPerRow: bytesPerRow,
				space: colorSpace,
				bitmapInfo: bitmapInfo
			) else { return false }
			context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
			return true
		}
		return rendered ? bytes : nil
	}
}
