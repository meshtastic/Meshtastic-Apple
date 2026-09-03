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

	@Test("A refusal ends the BLE update and says what it means")
	func bleRefusal() {
		for refusal in Self.refusals {
			let model = ESP32BLEOTAViewModel()
			model.handleDeviceNotice(refusal)
			#expect(model.otaStatus == .error, "\(refusal) should end the update")
			#expect(model.deviceRefusal == model.statusMessage)
			#expect(model.deviceRefusal == OTARefusal.explanation(for: refusal),
					"\(refusal) should be explained, not repeated")
		}
	}

	@Test("Every refusal the firmware can send is explained")
	func everyRefusalIsExplained() {
		for refusal in Self.refusals {
			let explanation = OTARefusal.explanation(for: refusal)
			#expect(explanation != nil, "no explanation for: \(refusal)")
			// The firmware's own sentence for a missing loader reads as its opposite
			// ("Device does have a valid OTA Loader"), so it must not be passed through.
			#expect(explanation != refusal)
		}
	}

	@Test("An unrecognized message is shown but does not end the update")
	func unknownMessageDoesNotFailTheUpdate() {
		// Matching "OTA" alone would let an unrelated notification fail an update that is
		// going fine, and firmware wording changes, so only sentences we recognize are
		// treated as a refusal.
		#expect(OTARefusal.classify("Something new about OTA") == nil)
		let model = ESP32BLEOTAViewModel()
		model.handleDeviceNotice("Something new about OTA")
		#expect(model.statusMessage == "Something new about OTA")
		#expect(model.otaStatus != .error)
		#expect(model.deviceRefusal == nil)
	}

	@Test("A refusal is what ends the update, on both transports")
	func onlyRefusalsAreTerminal() {
		for refusal in Self.refusals {
			guard case .refused = OTARefusal.classify(refusal) else {
				Issue.record("\(refusal) should classify as a refusal")
				continue
			}
		}
		guard case .progress = OTARefusal.classify("Rebooting to BLE OTA") else {
			Issue.record("going into update mode is progress, not a refusal")
			return
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
		#expect(model.deviceRefusal != nil)
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
			#expect(model.errorMessage == OTARefusal.explanation(for: refusal))
			#expect(model.deviceRefusal == model.errorMessage)
		}
	}

	@Test("A notice arriving after the update finished changes nothing")
	func noticeAfterCompletionIsIgnored() {
		let model = ESP32WifiOTAViewModel()
		model.otaState = .completed
		model.statusMessage = "Success! Rebooting..."

		model.handleDeviceNotice("Cannot start OTA: Cannot find OTA Loader partition.")

		#expect(model.otaState == .completed, "a finished update is not undone by a late notice")
		#expect(model.statusMessage == "Success! Rebooting...")
		#expect(model.errorMessage == nil)
		#expect(model.deviceRefusal == nil)
	}

	@Test("A notice arriving after a failure does not replace the failure")
	func noticeAfterFailureIsIgnored() {
		let model = ESP32BLEOTAViewModel()
		model.handleDeviceNotice("OTA Loader does not support BLE")
		let firstReason = model.deviceRefusal

		model.handleDeviceNotice("Cannot start OTA: Invalid `ota_hash` provided.")

		#expect(model.deviceRefusal == firstReason, "the first reason is the real one")
	}
}
