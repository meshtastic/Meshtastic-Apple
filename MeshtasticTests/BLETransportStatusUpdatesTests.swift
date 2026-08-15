//
//  BLETransportStatusUpdatesTests.swift
//  MeshtasticTests
//
//  Covers statusUpdates() (#2175). #2161/#2163 already fixed BLETransport.status to correctly
//  settle on .error("Bluetooth is powered off") instead of being immediately overwritten, but
//  nothing outside the actor could observe that value changing — so it never reached the UI.
//  AccessoryManager.observeBLETransportStatus() consumes this stream to mirror status onto a
//  @Published property the Connect tab reads (isBluetoothPoweredOff).
//

import CoreBluetooth
import Testing

@testable import Meshtastic

// A hung `iterator.next()` (e.g. a regression that stops a transition from ever arriving) would
// otherwise suspend a `@Test` indefinitely instead of failing — bound the whole suite with
// Swift Testing's own time limit rather than hand-rolling cancellation/racing around individual
// stream reads, which is easy to get subtly wrong around AsyncStream's single-consumer contract.
@Suite("BLETransport.statusUpdates()", .timeLimit(.minutes(1)))
struct BLETransportStatusUpdatesTests {

	/// `handleCentralState` only touches its `central:` parameter in the `.poweredOn` branch
	/// (to restart scanning); every other branch never reads it. A plain, delegate-less manager
	/// is enough to satisfy the signature without touching real Bluetooth hardware/authorization.
	private func unusedCentralManager() -> CBCentralManager {
		CBCentralManager(delegate: nil, queue: nil)
	}

	/// `BLETransport()` creates a *real* `CBCentralManager` on its own delegate whenever
	/// `CBCentralManager.authorization` is already determined — true on the simulator, where
	/// there's no real permission prompt to wait on. That manager asynchronously reports genuine
	/// (simulator) hardware state — typically `.unsupported`, since simulators have no real radio
	/// — independently of anything a test does. Those incidental values can land in the stream
	/// interleaved with a test's own explicit `handleCentralState` calls, so assertions must drain
	/// for the expected value rather than assume it's the very next element.
	private func drainUntil(
		_ expected: TransportStatus,
		from iterator: inout AsyncStream<TransportStatus>.AsyncIterator,
		attempts: Int = 10
	) async -> Bool {
		for _ in 0..<attempts {
			guard let value = await iterator.next() else { return false }
			if value == expected { return true }
		}
		return false
	}

	@Test func immediatelyYieldsCurrentStatus() async {
		let transport = BLETransport()
		let stream = await transport.statusUpdates()
		var iterator = stream.makeAsyncIterator()

		// The very first element must be *a* status (the replay), not a hang waiting on a
		// transition — the real value can legitimately be .uninitialized or the simulator's
		// own incidental .unsupported depending on timing (see drainUntil above).
		let first = await iterator.next()
		#expect(first != nil, "a late subscriber must see a status right away, not wait for the next transition")
	}

	@Test func yieldsOnStatusChange() async {
		let transport = BLETransport()
		let stream = await transport.statusUpdates()
		var iterator = stream.makeAsyncIterator()

		await transport.handleCentralState(.poweredOff, central: unusedCentralManager())

		let sawExpected = await drainUntil(.error(BLETransport.poweredOffStatusMessage), from: &iterator)
		#expect(sawExpected, "statusUpdates() must eventually carry the .poweredOff transition")
	}

	/// The `status` `didSet` guards on an actual change before yielding — repeating the same
	/// CoreBluetooth state (which can happen; CBCentralManagerDelegate doesn't guarantee distinct
	/// states) must not enqueue a duplicate value that a late-arriving subscriber would trip over.
	@Test func doesNotYieldADuplicateForAnUnchangedStatus() async {
		let transport = BLETransport()
		let manager = unusedCentralManager()

		await transport.handleCentralState(.poweredOff, central: manager)

		let stream = await transport.statusUpdates()
		var iterator = stream.makeAsyncIterator()

		// Replay of the current .error status from the subscribe-time yield (possibly preceded
		// by incidental simulator-hardware values — drain until we see it).
		let sawReplay = await drainUntil(.error(BLETransport.poweredOffStatusMessage), from: &iterator)
		#expect(sawReplay)

		// A second, identical .poweredOff must not produce a second queued value.
		await transport.handleCentralState(.poweredOff, central: manager)

		// A real change afterward proves the duplicate was swallowed: count how many further
		// .error(poweredOff) values arrive before .discovering shows up. Zero means the repeat
		// never got queued; any more than zero means it leaked through.
		await transport.handleCentralState(.poweredOn, central: manager)
		var duplicateCount = 0
		var sawDiscovering = false
		for _ in 0..<10 {
			guard let value = await iterator.next() else { break }
			if value == .discovering { sawDiscovering = true; break }
			if value == .error(BLETransport.poweredOffStatusMessage) { duplicateCount += 1 }
		}
		#expect(sawDiscovering)
		#expect(duplicateCount == 0, "the repeated .poweredOff must have been swallowed by didSet's equality guard")
	}

	/// Only `AccessoryManager` is expected to subscribe; a second `statusUpdates()` call replaces
	/// the stored continuation, so the earlier stream stops receiving new values instead of both
	/// streams staying live indefinitely.
	@Test func aSecondSubscriberReplacesTheFirst() async {
		let transport = BLETransport()
		let manager = unusedCentralManager()

		let firstStream = await transport.statusUpdates()
		var firstIterator = firstStream.makeAsyncIterator()
		_ = await firstIterator.next() // consume the initial replay

		let secondStream = await transport.statusUpdates()
		var secondIterator = secondStream.makeAsyncIterator()
		_ = await secondIterator.next() // consume the initial replay

		await transport.handleCentralState(.poweredOff, central: manager)

		let sawExpected = await drainUntil(.error(BLETransport.poweredOffStatusMessage), from: &secondIterator)
		#expect(sawExpected)
	}
}
