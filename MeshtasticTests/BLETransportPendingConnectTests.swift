//
//  BLETransportPendingConnectTests.swift
//  MeshtasticTests
//
//  The pending-connect bookkeeping that makes sure each BLE connect
//  continuation is resumed exactly once, and only by its own attempt.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("BLETransport pending connect slot")
struct BLETransportPendingConnectTests {

	// Plain values stand in for continuations; the slot only stores and hands them out.
	private typealias Slot = PendingConnectSlot<String>

	@Test func takeHandsOutTheContinuationOnce() {
		var slot = Slot()
		let peripheral = UUID()
		slot.begin(attempt: slot.nextAttempt(), peripheralId: peripheral, continuation: "a")

		#expect(slot.take(peripheralId: peripheral) == "a")
		#expect(slot.take(peripheralId: peripheral) == nil)
		#expect(slot.take() == nil)
		#expect(slot.isPending == false)
	}

	@Test func cancelAfterFinishDoesNothing() {
		var slot = Slot()
		let peripheral = UUID()
		let attempt = slot.nextAttempt()
		slot.begin(attempt: attempt, peripheralId: peripheral, continuation: "a")

		#expect(slot.take(peripheralId: peripheral) == "a")
		#expect(slot.take(attempt: attempt) == nil)
	}

	@Test func staleCancelLeavesRetryToSamePeripheralAlone() {
		var slot = Slot()
		let peripheral = UUID()
		let first = slot.nextAttempt()
		slot.begin(attempt: first, peripheralId: peripheral, continuation: "first")
		#expect(slot.take(peripheralId: peripheral) == "first")

		let retry = slot.nextAttempt()
		slot.begin(attempt: retry, peripheralId: peripheral, continuation: "retry")

		#expect(slot.take(attempt: first) == nil)
		#expect(slot.isPending)
		#expect(slot.take(attempt: retry) == "retry")
	}

	@Test func callbackForOtherPeripheralIsIgnored() {
		var slot = Slot()
		slot.begin(attempt: slot.nextAttempt(), peripheralId: UUID(), continuation: "a")

		#expect(slot.take(peripheralId: UUID()) == nil)
		#expect(slot.isPending)
	}
}
