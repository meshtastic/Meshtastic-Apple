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

	var description: String {
		switch self {
		case let .missingReference(url):
			"Missing snapshot reference at \(url.path). Run with TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS=1 to record it explicitly."
		case let .unreadableReference(url):
			"Unable to read snapshot reference at \(url.path)."
		case let .dimensionMismatch(reference, actual):
			"Snapshot dimensions changed from \(reference.width)×\(reference.height) to \(actual.width)×\(actual.height). Run with TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS=1 to replace the reference explicitly."
		}
	}
}

struct SnapshotReferenceStore {
	private let fileManager = FileManager.default

	func check(
		pngData: Data,
		pixelDimensions: SnapshotPixelDimensions,
		referenceURL: URL,
		mode: SnapshotReferenceMode
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
			  let referenceCGImage = referenceImage.cgImage else {
			throw SnapshotReferenceError.unreadableReference(referenceURL)
		}

		let referenceDimensions = SnapshotPixelDimensions(
			width: referenceCGImage.width,
			height: referenceCGImage.height
		)
		guard referenceDimensions == pixelDimensions else {
			throw SnapshotReferenceError.dimensionMismatch(
				reference: referenceDimensions,
				actual: pixelDimensions
			)
		}
	}
}
