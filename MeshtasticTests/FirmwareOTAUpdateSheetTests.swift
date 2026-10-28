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

	@Test("A dropped DFU starts over against a known bootloader, up to the restart limit")
	func testDFURestartPolicy() {
		#expect(DFURestartPolicy.shouldRestart(linkLost: true, bootloaderTargetKnown: true, restartsSoFar: 0))
		#expect(DFURestartPolicy.shouldRestart(linkLost: true, bootloaderTargetKnown: true, restartsSoFar: DFURestartPolicy.maxRestarts - 1))
		#expect(!DFURestartPolicy.shouldRestart(linkLost: true, bootloaderTargetKnown: true, restartsSoFar: DFURestartPolicy.maxRestarts))
	}

	@Test("A DFU error that is not a lost link, or with no bootloader to return to, does not restart")
	func testDFURestartPolicyRefuses() {
		#expect(!DFURestartPolicy.shouldRestart(linkLost: false, bootloaderTargetKnown: true, restartsSoFar: 0))
		#expect(!DFURestartPolicy.shouldRestart(linkLost: true, bootloaderTargetKnown: false, restartsSoFar: 0))
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
