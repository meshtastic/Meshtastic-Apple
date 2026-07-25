//
//  BLETransportRestoreStateTests.swift
//  MeshtasticTests
//
//  Covers the state-restoration teardown in BLETransport.handleWillRestoreState.
//
//  That method sets up four pieces of state — restoreInProgress, activeConnection,
//  restoredConnectContinuation and a discoveredPeripherals entry — but every failure path used
//  to reset exactly one of them (restoreInProgress), and the wait for didConnect was unbounded.
//  The common trigger is ordinary: the app is killed in the background while connected, iOS
//  relaunches it through willRestoreState with the peripheral in .connecting, and the radio is
//  off or out of range by then.
//
//  What is asserted here is the teardown contract: a restore that never connects has to end,
//  withdraw its CoreBluetooth connect request, and leave no pending continuation behind.
//
//  LIMITATION: CBPeripheral has no public initializer, so handleWillRestoreState itself can't be
//  driven from a test — it needs a real peripheral in the restore dictionary. These tests drive
//  the pieces it delegates to (beginRestore/awaitRestoredConnect/endRestore/
//  connectionDidDisconnect) with the same call sequence the restore task uses. The identity
//  checks added to handleDidConnect/handleDidFailToConnect are likewise not covered, for the
//  same reason.
//

import CoreBluetooth
import Foundation
import Testing

@testable import Meshtastic

/// A regression in any of these paths shows up as a suspension that never resumes, which would
/// hang a `@Test` rather than fail it. Bound the suite so it fails instead.
@Suite("BLETransport state restoration teardown", .timeLimit(.minutes(1)))
struct BLETransportRestoreStateTests {

	/// `cancelConnect` is a synchronous `@Sendable` closure (it wraps
	/// `CBCentralManager.cancelPeripheralConnection`), so it can't await an actor to record that
	/// it ran.
	private final class CallFlag: @unchecked Sendable {
		private let lock = NSLock()
		private var called = false

		func record() {
			lock.lock()
			called = true
			lock.unlock()
		}

		var wasCalled: Bool {
			lock.lock()
			defer { lock.unlock() }
			return called
		}
	}

	/// The restored connect installs its continuation before `connect()` returns, but the caller
	/// runs it on a task hop, so poll rather than sleeping a guessed interval.
	private func waitForPendingRestoredConnect(on transport: BLETransport) async -> Bool {
		for _ in 0..<300 {
			if await transport.isAwaitingRestoredConnect { return true }
			try? await Task.sleep(for: .milliseconds(10))
		}
		return false
	}

	/// The radio is powered off or out of range at relaunch: the connect request is issued and
	/// nothing ever comes back — no didConnect, no didFailToConnect, no didDisconnectPeripheral.
	/// CoreBluetooth connect requests don't expire, so the wait has to expire on its own,
	/// withdraw the request, and let the restore task run its teardown. Without that, all three
	/// scan entry points stay gated on restoreInProgress and BLE discovery is dead until the app
	/// is force-quit.
	@Test func aRestoredConnectThatNeverAnswersTimesOutAndWithdrawsTheRequest() async {
		let transport = BLETransport()
		let cancelled = CallFlag()
		await transport.beginRestore(for: UUID())

		var threw = false
		do {
			try await transport.awaitRestoredConnect(
				timeout: .milliseconds(300),
				connect: { /* radio absent: nothing will ever answer this */ },
				cancelConnect: { cancelled.record() }
			)
		} catch {
			threw = true
		}

		#expect(threw, "an unanswered restored connect must not suspend forever")
		#expect(cancelled.wasCalled, "the pending CoreBluetooth connect request must be withdrawn on timeout")
		#expect(await transport.isAwaitingRestoredConnect == false)

		// What the restore task's teardown then does, and the reason the timeout matters: the
		// discovery gate comes back down.
		await transport.endRestore(clearingConnection: true)
		#expect(await transport.restoreInProgress == false, "discovery stays suppressed for the life of the process if this latches")
	}

	/// `connectionDidDisconnect` is the single funnel for "this peripheral is gone". A restore
	/// waiting on didConnect will never get one after that, so the continuation has to be
	/// resolved here. Left pending, `handleDidConnect` resumes it in preference to the real
	/// `connectContinuation`, so the next legitimate connect is answered by the dead restore and
	/// hangs to its own timeout.
	@Test func aDisconnectResolvesAPendingRestoredConnect() async {
		let transport = BLETransport()
		await transport.beginRestore(for: UUID())

		let waiter = Task {
			try await transport.awaitRestoredConnect(
				timeout: .seconds(5),
				connect: { },
				cancelConnect: { }
			)
		}
		#expect(await waitForPendingRestoredConnect(on: transport))

		let start = ContinuousClock.now
		await transport.connectionDidDisconnect(fromPeripheral: nil)

		var threw = false
		do {
			try await waiter.value
		} catch {
			threw = true
		}
		let elapsed = ContinuousClock.now - start

		#expect(threw)
		// The disconnect itself has to resolve it. Falling through to the 5s watchdog instead
		// means the continuation was still live during the window a real connect would land in.
		#expect(elapsed < .seconds(2), "the disconnect must resolve the restored connect, not leave it for the timeout")
		#expect(await transport.isAwaitingRestoredConnect == false)
		#expect(await transport.restoreInProgress == false)
	}

	/// The restore task's `defer` calls `endRestore` on every exit, including exits that happen
	/// while the connect is still outstanding (a throw from the poweredOn gate, task
	/// cancellation). Nothing may be left suspended behind it.
	@Test func endingARestoreResolvesAPendingRestoredConnect() async {
		let transport = BLETransport()
		await transport.beginRestore(for: UUID())

		let waiter = Task {
			try await transport.awaitRestoredConnect(
				timeout: .seconds(5),
				connect: { },
				cancelConnect: { }
			)
		}
		#expect(await waitForPendingRestoredConnect(on: transport))

		let start = ContinuousClock.now
		await transport.endRestore(clearingConnection: true)

		var threw = false
		do {
			try await waiter.value
		} catch {
			threw = true
		}
		let elapsed = ContinuousClock.now - start

		#expect(threw)
		#expect(elapsed < .seconds(2))
		#expect(await transport.isAwaitingRestoredConnect == false)
		#expect(await transport.restoreInProgress == false)
	}

	/// Sanity check on the gate itself: begin/end are the only two writers, and the end has to
	/// actually re-open discovery.
	@Test func endingARestoreReopensDiscovery() async {
		let transport = BLETransport()

		await transport.beginRestore(for: UUID())
		#expect(await transport.restoreInProgress)

		await transport.endRestore(clearingConnection: true)
		#expect(await transport.restoreInProgress == false)
	}
}
