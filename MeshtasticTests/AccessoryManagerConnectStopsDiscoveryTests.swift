//
//  AccessoryManagerConnectStopsDiscoveryTests.swift
//  MeshtasticTests
//
//  Companion to AccessoryManagerScanDuringPairingTests.swift, which covers the
//  appDidBecomeActive() guard directly. This suite drives the real
//  AccessoryManager.connect(to:) pipeline (AccessoryManager+Connect.swift's SequentialSteps)
//  through Step 0 and Step 1, using a minimal mock Transport/Connection pair, to verify
//  Step 0's stopDiscovery() call actually *completes* — not merely gets requested — by the
//  time Step 1 hands control to the connection, on both the first attempt and a retry.
//
//  #2183 review (CodeRabbit): the original version of this suite only asserted
//  `discoveryTask == nil`, which is cleared synchronously by `stopDiscovery()` and proves
//  nothing about whether the underlying transport actually finished stopping — BLE's real
//  scan-stop happens via a detached, unawaited Task off `discoverDevices()`'s
//  `onTermination`. The fix: `Transport.stopActiveDiscovery()` (awaited by
//  `AccessoryManager.stopDiscovery()`) gives every transport an explicit, awaitable stop.
//  `MockBLETransportForConnectTests` below simulates that same async latency (a real
//  `Task.yield()`, not an immediate return) so this suite would fail if `stopDiscovery()`
//  ever stopped awaiting it.
//

import Foundation
import MeshtasticProtobufs
import Testing

@testable import Meshtastic

/// Records, from inside the mock connection's `connect()`, whether `AccessoryManager.discoveryTask`
/// was nil and how many of the mock transport's `stopActiveDiscovery()` calls had *completed*
/// (not merely started) at the moment Step 1 handed off. An actor so it's safe to mutate from
/// both the mock transport's and the mock connection's isolation.
actor DiscoveryStateRecorder {
	private(set) var discoveryTaskWasNilAtConnect: [Bool] = []
	private(set) var transportStopsCompletedAtConnect: [Int] = []
	private(set) var transportStopCompletedCount = 0

	func recordTransportStopCompleted() {
		transportStopCompletedCount += 1
	}

	func recordAtConnect(discoveryTaskWasNil: Bool) {
		discoveryTaskWasNilAtConnect.append(discoveryTaskWasNil)
		transportStopsCompletedAtConnect.append(transportStopCompletedCount)
	}
}

/// The minimum `Transport` conformance to satisfy `AccessoryManager.connect(to:)`'s
/// `transportForType` lookup and Step 8's `requiresPeriodicHeartbeat` read. `connect(to:)` itself
/// is never called — tests inject a `MockPairingConnection` directly via `withConnection:`.
///
/// `stopActiveDiscovery()` deliberately awaits a real suspension point (`Task.yield()`) before
/// recording completion, standing in for BLE's actor-hop-then-`centralManager.stopScan()`
/// latency. If `AccessoryManager.stopDiscovery()` ever stopped awaiting each transport's
/// `stopActiveDiscovery()` (e.g. reverted to fire-and-forget), this suite's ordering assertions
/// would fail.
final class MockBLETransportForConnectTests: Transport, @unchecked Sendable {
	let type: TransportType = .ble
	var status: TransportStatus { get async { .ready } }
	let requiresPeriodicHeartbeat = false
	let supportsManualConnection = false

	private let recorder: DiscoveryStateRecorder

	init(recorder: DiscoveryStateRecorder) {
		self.recorder = recorder
	}

	func discoverDevices() async -> AsyncStream<DiscoveryEvent> {
		AsyncStream { _ in }
	}

	func connect(to device: Device) async throws -> any Connection {
		throw AccessoryError.connectionFailed("MockBLETransportForConnectTests.connect(to:) should not be called; tests inject withConnection:")
	}

	func device(forManualConnection: String) -> Device? { nil }
	func manuallyConnect(toDevice: Device) async throws {}

	func stopActiveDiscovery() async {
		await Task.yield()
		await Task.yield()
		await recorder.recordTransportStopCompleted()
	}
}

/// A `Connection` whose `connect()` records discovery/transport-stop state at call time, then
/// always fails — the pipeline never needs to progress past Step 1 to answer the "was discovery
/// actually stopped before Step 1 handed off" question this suite is testing.
actor MockPairingConnection: Connection {
	let type: TransportType = .ble
	var isConnected: Bool = false

	private weak var accessoryManager: AccessoryManager?
	private let recorder: DiscoveryStateRecorder

	init(accessoryManager: AccessoryManager, recorder: DiscoveryStateRecorder) {
		self.accessoryManager = accessoryManager
		self.recorder = recorder
	}

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		let discoveryTaskWasNil = await accessoryManager?.discoveryTask == nil
		await recorder.recordAtConnect(discoveryTaskWasNil: discoveryTaskWasNil)
		throw AccessoryError.connectionFailed("MockPairingConnection always fails — discovery-timing probe only")
	}

	func send(_ data: ToRadio) async throws {}
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {}
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("AccessoryManager.connect(to:) stops discovery before Step 1")
struct AccessoryManagerConnectStopsDiscoveryTests {

	private func makeDevice() -> Device {
		Device(id: UUID(), name: "Mock Radio", transportType: .ble, identifier: UUID().uuidString)
	}

	/// Direct, isolated coverage of `AccessoryManager.stopDiscovery()` itself — asserting the
	/// mock transport's stop had completed *immediately after* `stopDiscovery()`'s `await`
	/// returns, rather than only inferring it transitively through the full `connect()`
	/// pipeline's Step 1 handoff. The pipeline-level tests below remain useful as end-to-end
	/// coverage, but `SequentialSteps`' own scheduling gaps mean they don't reliably fail if
	/// `stopDiscovery()` regressed to a fire-and-forget `Task { await transport.stopActiveDiscovery() }`
	/// instead of a real `for transport in transports { await transport.stopActiveDiscovery() }`
	/// — this test does.
	@Test func stopDiscoveryAwaitsTransportStopBeforeReturning() async {
		let recorder = DiscoveryStateRecorder()
		let manager = AccessoryManager(transports: [MockBLETransportForConnectTests(recorder: recorder)])
		manager.startDiscovery()
		#expect(manager.discoveryTask != nil)

		await manager.stopDiscovery()

		#expect(manager.discoveryTask == nil)
		#expect(await recorder.transportStopCompletedCount == 1)
	}

	@Test func stopsDiscoveryBeforeTheFirstConnectAttempt() async throws {
		let recorder = DiscoveryStateRecorder()
		let manager = AccessoryManager(transports: [MockBLETransportForConnectTests(recorder: recorder)])
		manager.startDiscovery()
		#expect(manager.discoveryTask != nil)

		let device = makeDevice()
		let connection = MockPairingConnection(accessoryManager: manager, recorder: recorder)

		// A single attempt (retries: 1) is enough to answer "was discovery off by Step 1" —
		// no need to pay the retry delay here. AccessoryManager.connect(to:) catches its own
		// step failures internally (surfacing them via lastConnectionError) rather than
		// rethrowing, so it does not throw here even though Step 1 always fails.
		try await manager.connect(
			to: device,
			withConnection: connection,
			wantConfig: false,
			wantDatabase: false,
			versionCheck: false,
			retries: 1
		)

		#expect(manager.lastConnectionError != nil)
		#expect(await recorder.discoveryTaskWasNilAtConnect == [true])
		// The real, load-bearing assertion: by the time Connection.connect() ran, the mock
		// transport's stopActiveDiscovery() had actually completed (its Task.yield()s had
		// resumed and recordTransportStopCompleted() had run) — not merely been requested.
		#expect(await recorder.transportStopsCompletedAtConnect == [1])
	}

	@Test func stopsDiscoveryBeforeEveryRetriedConnectAttempt() async throws {
		let recorder = DiscoveryStateRecorder()
		let manager = AccessoryManager(transports: [MockBLETransportForConnectTests(recorder: recorder)])
		manager.startDiscovery()

		let device = makeDevice()
		let connection = MockPairingConnection(accessoryManager: manager, recorder: recorder)

		// retries: 2 forces exactly one retry (SequentialSteps.run() iterates 0..<maxRetries),
		// so Step 0 — and its awaited stopDiscovery() call — runs twice: once for the first
		// attempt, once after closeConnection() re-arms discovery ahead of the retry. Same
		// non-throwing note as above applies here.
		try await manager.connect(
			to: device,
			withConnection: connection,
			wantConfig: false,
			wantDatabase: false,
			versionCheck: false,
			retries: 2
		)

		#expect(manager.lastConnectionError != nil)
		#expect(await recorder.discoveryTaskWasNilAtConnect == [true, true])
		// Per-attempt determinism: by attempt 1's Step 1 handoff exactly 1 stop had completed;
		// by attempt 2's, exactly 2 — proving Step 0 awaits a *fresh* completed stop on every
		// attempt, not just the first.
		#expect(await recorder.transportStopsCompletedAtConnect == [1, 2])
	}

	/// #2183 review (CodeRabbit): startDiscovery() must not race a fresh scan against a
	/// still-in-flight stopDiscovery() call. discoveryTask is cleared synchronously near the top
	/// of stopDiscovery(), before the (awaited) per-transport teardown loop even starts, so
	/// `discoveryTask == nil` alone was never a safe "fully stopped" signal for a concurrent
	/// caller to restart on.
	@Test func startDiscoveryNoOpsWhileAStopIsInFlight() async {
		let recorder = DiscoveryStateRecorder()
		let manager = AccessoryManager(transports: [MockBLETransportForConnectTests(recorder: recorder)])
		manager.startDiscovery()
		#expect(manager.discoveryTask != nil)

		// Kick off stopDiscovery() without awaiting it yet, then yield once. stopDiscovery()'s
		// prefix (isStoppingDiscovery = true, discoveryTask cleared) is entirely synchronous —
		// everything up to its first await (inside the mock's stopActiveDiscovery()) runs before
		// that first suspension, so by the time this yield's continuation resumes, that prefix has
		// deterministically already executed.
		let stopTask = Task { await manager.stopDiscovery() }
		await Task.yield()

		#expect(manager.discoveryTask == nil)
		#expect(manager.isStoppingDiscovery)

		// A concurrent caller (e.g. appDidBecomeActive() after a background/foreground toggle)
		// must not start a fresh scan while the previous stop is still winding down.
		manager.startDiscovery()
		#expect(manager.discoveryTask == nil)

		await stopTask.value
		#expect(manager.isStoppingDiscovery == false)
		#expect(await recorder.transportStopCompletedCount == 1)
	}
}
