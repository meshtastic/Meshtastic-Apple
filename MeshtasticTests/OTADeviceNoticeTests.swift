//
//  OTADeviceNoticeTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/2/26.
//

import Testing
import Foundation
@testable import Meshtastic

/// The firmware answers an OTA request with a client notification saying what it did — going
/// into update mode, or why it would not. The update sheets show that instead of waiting to
/// time out on a device that was never coming back.
@Suite("OTA device notices")
@MainActor
struct OTADeviceNoticeTests {

	private static let refusals = [
		"Cannot start OTA: Invalid `ota_hash` provided.",
		"Cannot start OTA: Cannot find OTA Loader partition.",
		"Cannot start OTA: Device does have a valid OTA Loader.",
		"OTA Loader does not support BLE",
		"Unable to switch to the OTA partition."
	]

	@Test("A refusal ends the BLE update with the radio's own words")
	func bleRefusal() {
		for refusal in Self.refusals {
			let model = ESP32BLEOTAViewModel()
			model.handleDeviceNotice(refusal)
			#expect(model.otaStatus == .error, "\(refusal) should end the update")
			#expect(model.statusMessage == refusal)
			#expect(model.deviceRefusal == refusal)
		}
	}

	@Test("Going into update mode is not a failure")
	func bleRebootNotice() {
		let model = ESP32BLEOTAViewModel()
		model.handleDeviceNotice("Rebooting to BLE OTA")
		#expect(model.otaStatus != .error)
		#expect(model.deviceRefusal == nil)
		#expect(model.statusMessage == "Rebooting to BLE OTA")
	}

	@Test("Retry clears the refusal")
	func bleRetryClears() {
		let model = ESP32BLEOTAViewModel()
		model.handleDeviceNotice("OTA Loader does not support BLE")
		model.retry()
		#expect(model.deviceRefusal == nil)
		#expect(model.otaStatus == .idle)
	}

	@Test("A refusal ends the Wi-Fi update with the radio's own words")
	func wifiRefusal() {
		for refusal in Self.refusals {
			let model = ESP32WifiOTAViewModel()
			model.handleDeviceNotice(refusal)
			#expect(model.otaState == .error, "\(refusal) should end the update")
			#expect(model.errorMessage == refusal)
			#expect(model.deviceRefusal == refusal)
		}
	}

	@Test("Wi-Fi ignores a notice once the update already finished")
	func wifiIgnoresAfterCompletion() {
		let model = ESP32WifiOTAViewModel()
		model.handleDeviceNotice("Rebooting to WiFi OTA")
		model.retry()
		#expect(model.otaState == .idle)
	}
}
