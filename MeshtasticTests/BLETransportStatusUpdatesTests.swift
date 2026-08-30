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

	/// Every test here scripts `status` transitions by calling `handleCentralState` directly, so
	/// the transport must not also own a real `CBCentralManager`: that manager reports the host's
	/// genuine Bluetooth state on its own schedule, and the resulting `handleCentralState` call
	/// lands in `status` at an arbitrary point between a test's own statements.
	private func scriptedTransport() -> BLETransport {
		BLETransport(createCentralManagerImmediately: false)
	}

	@Test func immediatelyYieldsCurrentStatus() async {
		let transport = scriptedTransport()
		let stream = await transport.statusUpdates()
		var iterator = stream.makeAsyncIterator()

		// A late subscriber must see the current status right away rather than waiting on the
		// next transition — nothing has been scripted yet, so that's the initial value.
		let first = await iterator.next()
		#expect(first == .uninitialized, "a late subscriber must see a status right away, not wait for the next transition")
	}

	@Test func yieldsOnStatusChange() async {
		let transport = scriptedTransport()
		let stream = await transport.statusUpdates()
		var iterator = stream.makeAsyncIterator()

		#expect(await iterator.next() == .uninitialized) // the subscribe-time replay

		await transport.handleCentralState(.poweredOff, central: unusedCentralManager())

		let next = await iterator.next()
		#expect(next == .error(BLETransport.poweredOffStatusMessage), "statusUpdates() must carry the .poweredOff transition")
	}

	/// The `status` `didSet` guards on an actual change before yielding — repeating the same
	/// CoreBluetooth state (which can happen; CBCentralManagerDelegate doesn't guarantee distinct
	/// states) must not enqueue a duplicate value that a late-arriving subscriber would trip over.
	@Test func doesNotYieldADuplicateForAnUnchangedStatus() async {
		let transport = scriptedTransport()
		let manager = unusedCentralManager()

		await transport.handleCentralState(.poweredOff, central: manager)

		let stream = await transport.statusUpdates()
		var iterator = stream.makeAsyncIterator()

		// Replay of the current .error status from the subscribe-time yield.
		#expect(await iterator.next() == .error(BLETransport.poweredOffStatusMessage))

		// A second, identical .poweredOff must not produce a second queued value.
		await transport.handleCentralState(.poweredOff, central: manager)

		// A real change afterward proves the duplicate was swallowed: if the repeat had been
		// queued it would be sitting ahead of .discovering in the stream.
		await transport.handleCentralState(.poweredOn, central: manager)

		let next = await iterator.next()
		#expect(next == .discovering, "the repeated .poweredOff must have been swallowed by didSet's equality guard")
	}

	/// Only `AccessoryManager` is expected to subscribe; a second `statusUpdates()` call replaces
	/// the stored continuation, so the earlier stream stops receiving new values instead of both
	/// streams staying live indefinitely.
	@Test func aSecondSubscriberReplacesTheFirst() async {
		let transport = scriptedTransport()
		let manager = unusedCentralManager()

		let firstStream = await transport.statusUpdates()
		var firstIterator = firstStream.makeAsyncIterator()
		#expect(await firstIterator.next() == .uninitialized) // consume the initial replay

		let secondStream = await transport.statusUpdates()
		var secondIterator = secondStream.makeAsyncIterator()
		#expect(await secondIterator.next() == .uninitialized) // consume the initial replay

		await transport.handleCentralState(.poweredOff, central: manager)

		let next = await secondIterator.next()
		#expect(next == .error(BLETransport.poweredOffStatusMessage))
	}
}
