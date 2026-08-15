import Foundation
import Testing
import UIKit

@Suite("Snapshot reference storage")
struct SnapshotReferenceStoreTests {

	@Test("Verification does not create a missing reference")
	func verificationDoesNotCreateMissingReference() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let referenceURL = directory.appendingPathComponent("missing.png")
		defer { try? FileManager.default.removeItem(at: directory) }

		do {
			try SnapshotReferenceStore().check(
				pngData: Data("snapshot".utf8),
				pixelDimensions: SnapshotPixelDimensions(width: 1, height: 1),
				referenceURL: referenceURL,
				mode: .verify
			)
			Issue.record("Verification unexpectedly accepted a missing reference")
		} catch let error as SnapshotReferenceError {
			#expect(error == .missingReference(referenceURL))
		}

		#expect(!FileManager.default.fileExists(atPath: referenceURL.path))
		#expect(!FileManager.default.fileExists(atPath: directory.path))
	}

	@Test("Recording mode requires an explicit environment value")
	func recordingModeRequiresExplicitEnvironmentValue() {
		#expect(SnapshotReferenceMode.current(environment: [:]) == .verify)
		#expect(SnapshotReferenceMode.current(environment: ["MESHTASTIC_RECORD_SNAPSHOTS": "0"]) == .verify)
		#expect(SnapshotReferenceMode.current(environment: ["MESHTASTIC_RECORD_SNAPSHOTS": "1"]) == .record)
		#expect(SnapshotReferenceMode.current(environment: ["TEST_RUNNER_MESHTASTIC_RECORD_SNAPSHOTS": "1"]) == .record)
	}

	@Test("iOS references keep their existing paths")
	func iOSReferencesKeepExistingPaths() {
		let testFileURL = URL(fileURLWithPath: "/repo/MeshtasticTests/SwiftUIViewSnapshotTests.swift")

		let testReference = SnapshotReferencePath.referenceURL(
			testFileURL: testFileURL,
			snapshotName: "card",
			forDocs: false,
			platform: .iOS
		)
		#expect(testReference.path == "/repo/MeshtasticTests/__Snapshots__/SwiftUIViewSnapshotTests/card.png")

		let docsReference = SnapshotReferencePath.referenceURL(
			testFileURL: testFileURL,
			snapshotName: "card",
			forDocs: true,
			platform: .iOS
		)
		#expect(docsReference.path == "/repo/docs/assets/screenshots/card.png")
	}

	@Test("Mac Catalyst references use separate directories")
	func macCatalystReferencesUseSeparateDirectories() {
		let testFileURL = URL(fileURLWithPath: "/repo/MeshtasticTests/SwiftUIViewSnapshotTests.swift")

		let testReference = SnapshotReferencePath.referenceURL(
			testFileURL: testFileURL,
			snapshotName: "card",
			forDocs: false,
			platform: .macCatalyst
		)
		#expect(testReference.path == "/repo/MeshtasticTests/__Snapshots__/SwiftUIViewSnapshotTests/macCatalyst/card.png")

		let docsReference = SnapshotReferencePath.referenceURL(
			testFileURL: testFileURL,
			snapshotName: "card",
			forDocs: true,
			platform: .macCatalyst
		)
		#expect(docsReference.path == "/repo/docs/assets/screenshots/macCatalyst/card.png")
	}

	@Test("Recording creates and replaces a reference")
	func recordingCreatesAndReplacesReference() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let referenceURL = directory.appendingPathComponent("recorded.png")
		defer { try? FileManager.default.removeItem(at: directory) }

		let firstData = try pngData(width: 1, height: 1)
		try SnapshotReferenceStore().check(
			pngData: firstData,
			pixelDimensions: SnapshotPixelDimensions(width: 1, height: 1),
			referenceURL: referenceURL,
			mode: .record
		)
		#expect(try Data(contentsOf: referenceURL) == firstData)

		let replacementData = try pngData(width: 2, height: 1)
		try SnapshotReferenceStore().check(
			pngData: replacementData,
			pixelDimensions: SnapshotPixelDimensions(width: 2, height: 1),
			referenceURL: referenceURL,
			mode: .record
		)
		#expect(try Data(contentsOf: referenceURL) == replacementData)
	}

	@Test("Verification does not replace a reference with different dimensions")
	func verificationDoesNotReplaceDimensionMismatch() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let referenceURL = directory.appendingPathComponent("existing.png")
		defer { try? FileManager.default.removeItem(at: directory) }

		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let referenceData = try pngData(width: 1, height: 1)
		try referenceData.write(to: referenceURL)
		let newData = try pngData(width: 2, height: 1)

		do {
			try SnapshotReferenceStore().check(
				pngData: newData,
				pixelDimensions: SnapshotPixelDimensions(width: 2, height: 1),
				referenceURL: referenceURL,
				mode: .verify
			)
			Issue.record("Verification unexpectedly accepted different dimensions")
		} catch let error as SnapshotReferenceError {
			#expect(error == .dimensionMismatch(
				reference: SnapshotPixelDimensions(width: 1, height: 1),
				actual: SnapshotPixelDimensions(width: 2, height: 1)
			))
		}

		#expect(try Data(contentsOf: referenceURL) == referenceData)
	}

	private func pngData(width: Int, height: Int) throws -> Data {
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
			UIColor.systemBlue.setFill()
			context.fill(CGRect(x: 0, y: 0, width: width, height: height))
		}
		return try #require(image.pngData())
	}
}
