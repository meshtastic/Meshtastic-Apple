//
//  OTAFIXDriveWriterTests.swift
//  MeshtasticTests
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("OTAFIX drive writer")
struct OTAFIXDriveWriterTests {

	@Test func coordinatesTheSelectedDestinationBeforeWritingTheImage() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let destination = directory.appendingPathComponent("update-t1000_e_bootloader.uf2")
		let coordinatedDestination = directory.appendingPathComponent("coordinated-update.uf2")
		let coordinator = RecordingCoordinator(coordinatedDestination: coordinatedDestination)
		let image = Data([0x55, 0x46, 0x32])

		try OTAFIXDriveWriter.write(image, to: destination, coordinator: coordinator)

		#expect(coordinator.requestedDestination == destination)
		#expect(coordinator.didInvokeAccessor)
		#expect(try Data(contentsOf: coordinatedDestination) == image)
		#expect(!FileManager.default.fileExists(atPath: destination.path))
	}

	@Test func reportsAWriteErrorFromTheSelectedDestination() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		#expect(throws: Error.self) {
			try OTAFIXDriveWriter.write(Data([0x55]), to: directory)
		}
	}

	@Test func reportsACoordinationError() {
		#expect(throws: TestError.self) {
			try OTAFIXDriveWriter.write(
				Data([0x55]),
				to: URL(fileURLWithPath: "/selected-drive/update.uf2"),
				coordinator: FailingCoordinator()
			)
		}
	}
}

private final class RecordingCoordinator: OTAFIXDriveWriteCoordinating {
	let coordinatedDestination: URL
	private(set) var requestedDestination: URL?
	private(set) var didInvokeAccessor = false

	init(coordinatedDestination: URL) {
		self.coordinatedDestination = coordinatedDestination
	}

	func coordinateWritingItem(at destination: URL, accessor: (URL) -> Void) throws {
		requestedDestination = destination
		didInvokeAccessor = true
		accessor(coordinatedDestination)
	}
}

private struct FailingCoordinator: OTAFIXDriveWriteCoordinating {
	func coordinateWritingItem(at destination: URL, accessor: (URL) -> Void) throws {
		throw TestError.coordinationFailed
	}
}

private enum TestError: Error {
	case coordinationFailed
}
