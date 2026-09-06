//
//  LoRaRebootCapabilityTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Testing
import Foundation
@testable import Meshtastic

/// Covers `AccessoryManager.appliesLoRaConfigWithoutReboot`.
///
/// Firmware 2.8 applies LoRa changes live, so the connection survives a save. The gate has to stay
/// conservative when the firmware version is unknown: assuming no reboot there drops the warning
/// before a reboot the user did not expect, and turns a genuine post-save failure into a shrug.
@Suite("LoRa save reboot capability")
@MainActor
struct LoRaRebootCapabilityTests {

	private func withFirmwareVersion(_ version: String?, _ body: () -> Void) {
		let previous = UserDefaults.firmwareVersion
		UserDefaults.firmwareVersion = version ?? "0.0.0"
		defer { UserDefaults.firmwareVersion = previous }
		body()
	}

	@Test("2.8 and later apply LoRa config without a reboot")
	func liveApplyOnTwoEight() {
		for version in ["2.8.0", "2.8.1", "2.9.0", "3.0.0"] {
			withFirmwareVersion(version) {
				#expect(AccessoryManager.shared.appliesLoRaConfigWithoutReboot, "expected no reboot on \(version)")
			}
		}
	}

	@Test("firmware before 2.8 still reboots on a LoRa save")
	func rebootsBeforeTwoEight() {
		for version in ["2.7.21", "2.7.0", "2.6.17"] {
			withFirmwareVersion(version) {
				#expect(!AccessoryManager.shared.appliesLoRaConfigWithoutReboot, "expected a reboot on \(version)")
			}
		}
	}

	@Test("an unknown firmware version assumes a reboot")
	func unknownAssumesReboot() {
		// The other capability gates are permissive when the version is unknown, because showing a
		// feature early is cheap. Here the permissive answer is the harmful one.
		withFirmwareVersion(nil) {
			#expect(!AccessoryManager.shared.appliesLoRaConfigWithoutReboot)
		}
	}
}
