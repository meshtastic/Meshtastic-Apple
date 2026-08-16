//
//  FirmwareOTAUpdateSheetTests.swift
//  MeshtasticTests
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("Firmware OTA & DFU Update Sheet Tests")
struct FirmwareOTAUpdateSheetTests {

	@Test("FirmwareUpdateTips has non-empty localized messages")
	func testFirmwareUpdateTipsContent() {
		#expect(!FirmwareUpdateTips.messages.isEmpty)
		for message in FirmwareUpdateTips.messages {
			#expect(!message.isEmpty)
		}
	}

	@Test("DFUUpdateState isError property correctly identifies error states")
	func testDFUUpdateStateError() {
		#expect(!DFUUpdateState.idle.isError)
		#expect(!DFUUpdateState.starting.isError)
		#expect(!DFUUpdateState.uploading.isError)
		#expect(!DFUUpdateState.success.isError)
		#expect(DFUUpdateState.error("Firmware CRC check failed").isError)
	}

	@Test("LocalOTAStatusCode descriptions match expected values")
	func testLocalOTAStatusCodes() {
		#expect(LocalOTAStatusCode.idle.rawValue == "Ready")
		#expect(LocalOTAStatusCode.waitingForConnection.rawValue == "Waiting for Connection")
		#expect(LocalOTAStatusCode.connected.rawValue == "Connected")
		#expect(LocalOTAStatusCode.preparing.rawValue == "Preparing")
		#expect(LocalOTAStatusCode.transferring.rawValue == "Uploading")
		#expect(LocalOTAStatusCode.completed.rawValue == "Completed")
		#expect(LocalOTAStatusCode.error.rawValue == "Error")
	}

	@Test("OTAMetadataItem structure and identification")
	func testOTAMetadataItem() {
		let item = OTAMetadataItem(label: "Target Firmware", value: "2.7.20.bin", isMonospaced: true)
		#expect(item.id == "Target Firmware")
		#expect(item.label == "Target Firmware")
		#expect(item.value == "2.7.20.bin")
		#expect(item.isMonospaced)
	}
}
