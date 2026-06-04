//
//  PacketStreamModelTests.swift
//  MeshtasticTests
//
//  Covers the bounded/paced buffer backing the Packet Stream (spec 012).
//

import Testing
@testable import Meshtastic

@Suite("PacketStreamBuffer")
struct PacketStreamModelTests {

	@Test("reveal moves pending into visible one at a time, in order")
	func revealPacesOneAtATime() {
		var buffer = PacketStreamBuffer<Int>(maxVisible: 1_000, maxPending: 120)
		buffer.enqueue([1, 2, 3])

		#expect(buffer.visible.isEmpty)
		#expect(buffer.reveal(1) == 1)
		#expect(buffer.visible == [1])
		#expect(buffer.reveal(1) == 1)
		#expect(buffer.visible == [1, 2])
		#expect(buffer.reveal(1) == 1)
		#expect(buffer.visible == [1, 2, 3])
		// Nothing left to reveal.
		#expect(buffer.reveal(1) == 0)
	}

	@Test("visible window never exceeds maxVisible; oldest evicted first (FR-011)")
	func visibleWindowIsCapped() {
		var buffer = PacketStreamBuffer<Int>(maxVisible: 1_000, maxPending: 120)
		buffer.appendVisible(Array(1...1_500))

		#expect(buffer.visible.count == 1_000)
		// Oldest 500 dropped; window is the most recent 1,000.
		#expect(buffer.visible.first == 501)
		#expect(buffer.visible.last == 1_500)
	}

	@Test("pending overflow drops oldest and flags overload (FR-022)")
	func pendingOverloadDropsOldest() {
		var buffer = PacketStreamBuffer<Int>(maxVisible: 1_000, maxPending: 120)
		buffer.enqueue(Array(1...500))

		#expect(buffer.pending.count == 120)
		#expect(buffer.pending.first == 381)   // most-recent 120 retained
		#expect(buffer.pending.last == 500)
		#expect(buffer.droppedDueToOverload)
	}

	@Test("reveal of a batch larger than pending reveals only what is available")
	func revealClampsToAvailable() {
		var buffer = PacketStreamBuffer<Int>(maxVisible: 1_000, maxPending: 120)
		buffer.enqueue([10, 20])
		#expect(buffer.reveal(5) == 2)
		#expect(buffer.visible == [10, 20])
		#expect(buffer.pending.isEmpty)
	}

	@Test("clear resets visible, pending, and overload flag")
	func clearResets() {
		var buffer = PacketStreamBuffer<Int>(maxVisible: 1_000, maxPending: 120)
		buffer.enqueue(Array(1...500))
		buffer.appendVisible([1, 2, 3])
		buffer.clear()
		#expect(buffer.visible.isEmpty)
		#expect(buffer.pending.isEmpty)
		#expect(!buffer.droppedDueToOverload)
	}
}
