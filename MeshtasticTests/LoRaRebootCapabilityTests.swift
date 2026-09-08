//
//  LoRaRebootCapabilityTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Testing
import Foundation
@testable import Meshtastic

/// Covers `AccessoryManager.appliesLoRaConfigWithoutReboot(liveVersion:)`.
///
/// Firmware 2.8 applies LoRa changes live, so the connection survives a save. The gate reads only
/// the live connection's version: `UserDefaults.firmwareVersion` is global rather than per radio,
/// so consulting it right after a radio switch would answer for the previous radio.
@Suite("LoRa save reboot capability")
struct LoRaRebootCapabilityTests {

	@Test("2.8 and later apply LoRa config without a reboot")
	func liveApplyOnTwoEight() {
		for version in ["2.8.0", "2.8.1", "2.8.1.3a0c08b", "2.9.0", "3.0.0"] {
			#expect(AccessoryManager.appliesLoRaConfigWithoutReboot(liveVersion: version),
					"expected no reboot on \(version)")
		}
	}

	@Test("firmware before 2.8 still reboots on a LoRa save")
	func rebootsBeforeTwoEight() {
		for version in ["2.7.21", "2.7.21.abc123f", "2.7.0", "2.6.17"] {
			#expect(!AccessoryManager.appliesLoRaConfigWithoutReboot(liveVersion: version),
					"expected a reboot on \(version)")
		}
	}

	@Test("no live version assumes a reboot")
	func unknownAssumesReboot() {
		// The reconnect window after switching radios is exactly when this is nil. Assuming no
		// reboot there answers for whatever radio was connected before; assuming a reboot merely
		// restores the old forgiving behavior until metadata arrives.
		#expect(!AccessoryManager.appliesLoRaConfigWithoutReboot(liveVersion: nil))
		#expect(!AccessoryManager.appliesLoRaConfigWithoutReboot(liveVersion: ""))
	}

	@Test("the stored global version has no influence")
	func storedVersionDoesNotLeakAcrossRadios() {
		// The switching-radio regression: a 2.8 radio was connected, its version persisted, then a
		// pre-2.8 radio connects and the live version is briefly unknown. The stored value must not
		// make the gate claim the new radio applies LoRa config live.
		let previous = UserDefaults.firmwareVersion
		defer { UserDefaults.firmwareVersion = previous }

		UserDefaults.firmwareVersion = "2.8.1"
		#expect(!AccessoryManager.appliesLoRaConfigWithoutReboot(liveVersion: nil))
		#expect(!AccessoryManager.appliesLoRaConfigWithoutReboot(liveVersion: "2.7.21"))
	}
}
