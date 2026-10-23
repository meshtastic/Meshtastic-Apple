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
	case unreadableSnapshot
	case dimensionMismatch(reference: SnapshotPixelDimensions, actual: SnapshotPixelDimensions)
	case pixelMismatch(SnapshotPixelComparison, tolerance: SnapshotPixelTolerance, images: SnapshotFailureImages)

	var description: String {
		switch self {
		case let .missingReference(url):
			"Missing snapshot reference at \(url.path). Run with TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS=1 to record it explicitly."
		case let .unreadableReference(url):
			"Unable to read snapshot reference at \(url.path)."
		case .unreadableSnapshot:
			"Unable to read the rendered snapshot."
		case let .dimensionMismatch(reference, actual):
			"Snapshot dimensions changed from \(reference.width)×\(reference.height) to \(actual.width)×\(actual.height). Run with TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS=1 to replace the reference explicitly."
		case let .pixelMismatch(comparison, tolerance, _):
			Self.pixelMismatchDescription(comparison, tolerance: tolerance)
		}
	}

	private static func pixelMismatchDescription(
		_ comparison: SnapshotPixelComparison,
		tolerance: SnapshotPixelTolerance
	) -> String {
		let origin = comparison.worstTileOrigin
		let tile = "\(tolerance.tileSize)×\(tolerance.tileSize) tile at (\(origin.x), \(origin.y))"
		return [
			"Snapshot pixels changed: \(comparison.maxDifferingPixelsInTile) pixels differ by more than \(tolerance.perChannel) in a color channel inside the \(tile), and at most \(tolerance.maxDifferingPixelsPerTile) may.",
			"\(comparison.differingPixelCount) of \(comparison.totalPixelCount) pixels changed in total; the largest channel difference is \(comparison.maxChannelDelta).",
			"The actual and diff images are attached to the test result.",
			"Run with TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS=1 to replace the reference explicitly."
		].joined(separator: " ")
	}
}

/// PNGs to attach to a failed pixel comparison.
struct SnapshotFailureImages: Equatable {
	let actualPNG: Data
	/// Changed pixels in red over a faded copy of the reference. Nil if encoding failed.
	let diffPNG: Data?
}

/// Pixel comparison is off unless `MESHTASTIC_COMPARE_SNAPSHOT_PIXELS=1` is set,
/// until the tolerance has been measured on the CI toolchain.
enum SnapshotPixelCheck {
	static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
		let variableNames = [
			"MESHTASTIC_COMPARE_SNAPSHOT_PIXELS",
			"TEST_RUNNER_MESHTASTIC_COMPARE_SNAPSHOT_PIXELS"
		]
		return variableNames.contains(where: { environment[$0] == "1" })
	}
}

struct SnapshotReferenceStore {
	private let fileManager = FileManager.default
	var comparesPixels = SnapshotPixelCheck.isEnabled()
	var tolerance: SnapshotPixelTolerance = .standard

	/// `comparePixels: false` skips the pixel check for one snapshot, for views
	/// that render the current date or time.
	func check(
		pngData: Data,
		pixelDimensions: SnapshotPixelDimensions,
		referenceURL: URL,
		mode: SnapshotReferenceMode,
		comparePixels: Bool = true
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
			  let reference = SnapshotBitmap(pngData: referenceData) else {
			throw SnapshotReferenceError.unreadableReference(referenceURL)
		}
		guard reference.dimensions == pixelDimensions else {
			throw SnapshotReferenceError.dimensionMismatch(
				reference: reference.dimensions,
				actual: pixelDimensions
			)
		}
		guard comparesPixels && comparePixels else {
			return
		}

		guard let actual = SnapshotBitmap(pngData: pngData) else {
			throw SnapshotReferenceError.unreadableSnapshot
		}
		guard actual.dimensions == reference.dimensions else {
			throw SnapshotReferenceError.dimensionMismatch(
				reference: reference.dimensions,
				actual: actual.dimensions
			)
		}

		let comparison = SnapshotBitmap.compare(reference: reference, actual: actual, tolerance: tolerance)
		// One line per snapshot so CI logs can be used to pick the tolerance.
		// swiftlint:disable:next disable_print
		print("SNAPSHOT_PIXELS \(referenceURL.lastPathComponent) changed=\(comparison.differingPixelCount)/\(comparison.totalPixelCount) worstTile=\(comparison.maxDifferingPixelsInTile) maxDelta=\(comparison.maxChannelDelta)")
		guard comparison.passes(tolerance) else {
			let diff = SnapshotBitmap.diffImage(
				reference: reference,
				actual: actual,
				perChannelTolerance: tolerance.perChannel
			)
			throw SnapshotReferenceError.pixelMismatch(
				comparison,
				tolerance: tolerance,
				images: SnapshotFailureImages(actualPNG: pngData, diffPNG: diff.pngData())
			)
		}
	}
}
