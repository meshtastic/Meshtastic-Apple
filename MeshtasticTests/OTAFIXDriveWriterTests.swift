//
//  OTAFIXDriveWriterTests.swift
//  MeshtasticTests
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("OTAFIX drive writer")
struct OTAFIXDriveWriterTests {

	@Test func writesTheDownloadedImageAtTheSelectedDestination() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let destination = directory.appendingPathComponent("update-t1000_e_bootloader.uf2")
		let image = Data([0x55, 0x46, 0x32])

		try OTAFIXDriveWriter.write(image, to: destination)

		#expect(try Data(contentsOf: destination) == image)
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
}
