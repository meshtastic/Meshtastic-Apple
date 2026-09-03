//
//  AsyncCentralDeadlineTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/2/26.
//

import Testing
import Foundation
import CoreBluetooth
@testable import Meshtastic

/// Every wait in the ESP32 BLE OTA path used to race a sleeping task against a Core
/// Bluetooth callback. A checked continuation ignores cancellation, so when the
/// deadline won, the task group waited forever on the operation it had just
/// cancelled. Both calls below hung indefinitely before; they must now end on their
/// own. The simulator has no Bluetooth, which is exactly the case that hung.
@Suite("ESP32 BLE OTA deadlines")
@MainActor
struct AsyncCentralDeadlineTests {

	private static let otaServiceId = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")

	@Test("Bluetooth being unavailable is reported at once, not after the deadline", .timeLimit(.minutes(1)))
	func powerOnWaitEnds() async {
		let central = AsyncCentral()
		let start = Date()
		var thrown: Error?
		do {
			try await central.waitUntilPoweredOn(timeout: 30)
		} catch {
			thrown = error
		}
		let elapsed = Date().timeIntervalSince(start)
		// The simulator has no Bluetooth, so the state is already terminal. A terminal state
		// produces no further callback: waiting out the deadline only delays the same answer.
		#expect(thrown as? BLEError == .poweredOff)
		#expect(elapsed < 5, "reported after \(elapsed)s against a 30s deadline")
	}

	@Test("Scanning for a device in OTA mode ends on its own", .timeLimit(.minutes(1)))
	func scanEnds() async {
		let central = AsyncCentral()
		let start = Date()
		var thrown: Error?
		do {
			_ = try await central.scan(for: Self.otaServiceId, timeout: 2)
		} catch {
			thrown = error
		}
		#expect(Date().timeIntervalSince(start) < 10)
		// Bluetooth off in the simulator reports itself rather than running the full
		// deadline; on a radio that never advertises this is .scanTimeout instead.
		#expect(thrown is BLEError)
	}
}
