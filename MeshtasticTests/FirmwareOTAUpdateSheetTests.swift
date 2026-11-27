//
//  FirmwareOTAUpdateSheetTests.swift
//  MeshtasticTests
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("Firmware OTA & DFU Update Sheet Tests")
struct FirmwareOTAUpdateSheetTests {

	@Test("ESP32 update states map onto the shared update screen's stages")
	func testStageFromOTAStatus() {
		#expect(FirmwareUpdateStage(LocalOTAStatusCode.idle) == .ready)
		#expect(FirmwareUpdateStage(LocalOTAStatusCode.waitingForConnection) == .preparing)
		#expect(FirmwareUpdateStage(LocalOTAStatusCode.connected) == .preparing)
		#expect(FirmwareUpdateStage(LocalOTAStatusCode.preparing) == .preparing)
		#expect(FirmwareUpdateStage(LocalOTAStatusCode.transferring) == .sending)
		#expect(FirmwareUpdateStage(LocalOTAStatusCode.completed) == .done)
		#expect(FirmwareUpdateStage(LocalOTAStatusCode.error) == .failed)
	}

	@Test("Closing asks for confirmation only while an update is under way")
	func testStageIsUnderWay() {
		#expect(FirmwareUpdateStage.preparing.isUnderWay)
		#expect(FirmwareUpdateStage.sending.isUnderWay)
		#expect(FirmwareUpdateStage.restarting.isUnderWay)
		#expect(!FirmwareUpdateStage.ready.isUnderWay)
		#expect(!FirmwareUpdateStage.done.isUnderWay)
		#expect(!FirmwareUpdateStage.failed.isUnderWay)
		#expect(!FirmwareUpdateStage.unavailable(reason: "x").isUnderWay)
	}

	@Test("The firmware version is read from release file names")
	func testFirmwareFileVersion() {
		#expect(FirmwareFileVersion.version(in: "firmware-seeed_wio_tracker_L1-2.8.3.eb99f95-ota.zip") == "2.8.3.eb99f95")
		#expect(FirmwareFileVersion.version(in: "firmware-heltec-v3-2.7.18.fb3bf78.bin") == "2.7.18.fb3bf78")
		#expect(FirmwareFileVersion.version(in: "firmware-rak4631-2.8.1.uf2") == "2.8.1")
		#expect(FirmwareFileVersion.version(in: "my-custom-build.zip") == nil)
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
		#expect(DFURestartPolicy.shouldRestart(linkLost: true, bootloaderTargetKnown: true, finishing: false, restartsSoFar: 0))
		#expect(DFURestartPolicy.shouldRestart(linkLost: true, bootloaderTargetKnown: true, finishing: false, restartsSoFar: DFURestartPolicy.maxRestarts - 1))
		#expect(!DFURestartPolicy.shouldRestart(linkLost: true, bootloaderTargetKnown: true, finishing: false, restartsSoFar: DFURestartPolicy.maxRestarts))
	}

	@Test("A DFU error that is not a lost link, with no bootloader to return to, or after a stop or activation, does not restart")
	func testDFURestartPolicyRefuses() {
		#expect(!DFURestartPolicy.shouldRestart(linkLost: false, bootloaderTargetKnown: true, finishing: false, restartsSoFar: 0))
		#expect(!DFURestartPolicy.shouldRestart(linkLost: true, bootloaderTargetKnown: false, finishing: false, restartsSoFar: 0))
		#expect(!DFURestartPolicy.shouldRestart(linkLost: true, bootloaderTargetKnown: true, finishing: true, restartsSoFar: 0))
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
}
