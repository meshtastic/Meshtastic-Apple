//
//  AccessoryManagerDatabaseStepCancellationTests.swift
//  MeshtasticTests
//
//  End-to-end companion to SequentialStepsCancellationTests.swift. Drives the real
//  AccessoryManager.connect(to:) pipeline through the exact trigger that exposed the
//  cancellation-as-success bug: a transport-level disconnect that arrives while Step 5
//  (sendWantDatabase, the pipeline's only `.retryStep` step) is parked on
//  firstDatabaseNodeInfoContinuation.
//
//  The `.disconnected` event path calls closeConnection() directly, without going through
//  cancelCurrentlyExecutingStep, so no externalError is recorded. closeConnection() resumes
//  the continuation with CancellationError and resets wantDatabaseGate to closed. Before this
//  change the machine treated that as Step 5 succeeding and moved on to Step 5a, which waited
//  on the gate that had just been reset and had no timeout, so connect() never returned and
//  connectionStepper was never cleared.
//

import Foundation
import MeshtasticProtobufs
import Testing

@testable import Meshtastic

/// Set by the task that calls `connect(to:)` once that call has returned, so the test can put a
/// bound on how long it waits without blocking on the task itself. Awaiting an unstructured
/// `Task`'s value cannot be abandoned, so a stuck `connect()` would hang the test rather than
/// fail it.
actor ConnectCompletionFlag {
	private(set) var didReturn = false

	func markReturned() {
		didReturn = true
	}
}

/// A `Connection` that completes Step 1, accepts the heartbeat and the database wantConfig,
/// then never delivers a NodeInfo, so Step 5 stays suspended until the test injects a
/// `.disconnected` event on the same event stream a real transport would use.
actor MockStallingDatabaseConnection: Connection {
	let type: TransportType = .ble
	private(set) var isConnected: Bool = false
	private(set) var sentDatabaseWantConfig = false

	private var eventContinuation: AsyncStream<ConnectionEvent>.Continuation?

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		isConnected = true
		var captured: AsyncStream<ConnectionEvent>.Continuation?
		let stream = AsyncStream<ConnectionEvent> { continuation in
			captured = continuation
		}
		eventContinuation = captured
		return stream
	}

	func send(_ data: ToRadio) async throws {
		// wantConfig is disabled in this test, so the only wantConfigID that reaches the
		// connection is Step 5's NONCE_ONLY_DB request.
		if case .wantConfigID = data.payloadVariant {
			sentDatabaseWantConfig = true
		}
	}

	/// Simulates the radio/link going away underneath a suspended Step 5.
	func emitDisconnected() {
		eventContinuation?.yield(.disconnected(shouldReconnect: false))
	}

	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {
		isConnected = false
		eventContinuation?.finish()
	}

	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("AccessoryManager.connect(to:) handles a cancelled wantDatabase step")
struct AccessoryManagerDatabaseStepCancellationTests {

	private func waitUntil(
		timeout: Duration = .seconds(5),
		_ condition: @Sendable () async -> Bool
	) async -> Bool {
		let deadline = ContinuousClock.now.advanced(by: timeout)
		while ContinuousClock.now < deadline {
			if await condition() { return true }
			try? await Task.sleep(for: .milliseconds(10))
		}
		return await condition()
	}

	private func makeDevice() -> Device {
		Device(id: UUID(), name: "Mock Radio", transportType: .ble, identifier: UUID().uuidString)
	}

	/// `AccessoryError` is not Equatable, so match the case rather than comparing values.
	private func isTooManyRetries(_ error: Error?) -> Bool {
		guard let accessoryError = error as? AccessoryError else { return false }
		if case .tooManyRetries = accessoryError { return true }
		return false
	}

	private func connectionFailedMessage(_ error: Error?) -> String? {
		guard let accessoryError = error as? AccessoryError,
			  case .connectionFailed(let message) = accessoryError else { return nil }
		return message
	}

	@Test func disconnectDuringWantDatabaseEndsTheConnectionAttempt() async throws {
		// connect() reaches Step 5, which writes UserDefaults.preferredPeripheralId, and its
		// one-time pairing migration can write migratedPreferredPeripheralPairing and
		// pairedPeripheralIds. Those are process-wide and are asserted on exactly by other suites
		// (BLEPairingHintTests), so restore them rather than leaving the mutation behind.
		let originalPreferredPeripheralId = UserDefaults.preferredPeripheralId
		let originalMigratedPairing = UserDefaults.migratedPreferredPeripheralPairing
		let originalPairedPeripheralIds = UserDefaults.pairedPeripheralIds
		defer {
			UserDefaults.preferredPeripheralId = originalPreferredPeripheralId
			UserDefaults.migratedPreferredPeripheralPairing = originalMigratedPairing
			UserDefaults.pairedPeripheralIds = originalPairedPeripheralIds
		}

		let recorder = DiscoveryStateRecorder()
		let manager = AccessoryManager(transports: [MockBLETransportForConnectTests(recorder: recorder)])
		let connection = MockStallingDatabaseConnection()

		let completion = ConnectCompletionFlag()
		let connectTask = Task { @MainActor in
			// retries: 1 keeps this to a single pass through the pipeline. versionCheck and
			// wantConfig are off so the run reaches Step 5 without needing a scripted radio.
			try? await manager.connect(
				to: makeDevice(),
				withConnection: connection,
				wantConfig: false,
				wantDatabase: true,
				versionCheck: false,
				retries: 1
			)
			await completion.markReturned()
		}

		// Wait for the real production state this test depends on: Step 5 has sent the request AND
		// is parked on firstDatabaseNodeInfoContinuation. sentDatabaseWantConfig flips inside the
		// mock's send(), two actor hops before the continuation is installed, so gating only on it
		// (or on a fixed sleep) lets emitDisconnected() land in the window where closeConnection()
		// finds a nil continuation and never cancels Step 5 at all.
		try #require(await waitUntil { await connection.sentDatabaseWantConfig })
		try #require(await waitUntil { await MainActor.run { manager.firstDatabaseNodeInfoContinuation != nil } })
		#expect(manager.state == .retrievingDatabase(nodeCount: 0))

		let teardownStart = ContinuousClock.now
		await connection.emitDisconnected()

		// connect() has to come back. Before the fix it stayed suspended in Step 5a forever,
		// waiting on a gate closeConnection() had already reset, with no timeout to break it.
		let connectReturned = await waitUntil(timeout: .seconds(10)) { await completion.didReturn }
		let teardownDuration = teardownStart.duration(to: .now)

		#expect(connectReturned)
		// The cancellation itself has to end the run. Step 5a's timeout is a second, much slower
		// backstop, and if the cancellation were still being treated as success the machine would
		// advance into that step and only unwind when it expired. Requiring a prompt return keeps
		// this test tied to the cancellation path rather than to the value of that timeout.
		#expect(teardownDuration < .seconds(5))
		// The failed step must not have been credited as a success: Step 7's .subscribed transition
		// never happens, and the machine ends in the failure terminal state rather than orphaned.
		#expect(manager.state == .discovering)
		#expect(manager.isConnected == false)
		#expect(manager.connectionStepper == nil)
		// The pipeline exhausted its single attempt after the cancelled step, so connect()'s
		// tooManyRetries handler is what recorded the error.
		#expect(isTooManyRetries(manager.lastConnectionError))

		// Drain the connect task so nothing from this run (closeConnection, startDiscovery) is
		// still touching shared state after the test returns. Only safe once connect() has
		// returned: the machine runs each step in an unstructured Task, so cancelling connectTask
		// cannot interrupt a stuck step and awaiting it would hang instead of fail.
		connectTask.cancel()
		if connectReturned {
			_ = await connectTask.value
		}
	}

	/// The reentrancy guard: connect() must refuse to run while a previous step machine is
	/// still going, instead of overwriting connectionStepper and leaving the old machine
	/// running against the same AccessoryManager.
	@Test func connectRefusesToStartWhileAPreviousStepperIsRunning() async {
		let recorder = DiscoveryStateRecorder()
		let manager = AccessoryManager(transports: [MockBLETransportForConnectTests(recorder: recorder)])

		let stuckStepper = SequentialSteps(maxRetries: 1, retryDelay: .milliseconds(10)) {
			Step { _ in
				try await Task.sleep(for: .seconds(30))
			}
		}
		let stuckRun = Task { try? await stuckStepper.run() }
		#expect(await waitUntil { await stuckStepper.isRunning })
		manager.connectionStepper = stuckStepper

		var thrownError: Error?
		do {
			try await manager.connect(
				to: makeDevice(),
				withConnection: MockStallingDatabaseConnection(),
				wantConfig: false,
				wantDatabase: false,
				versionCheck: false,
				retries: 1
			)
		} catch {
			thrownError = error
		}

		// All three of connect()'s early throws are AccessoryError.connectionFailed, distinguished
		// only by message, so assert the message the guard uses.
		#expect(connectionFailedMessage(thrownError) == "A connection attempt is already in progress")
		// The in-flight machine is still the one connectionStepper points at.
		#expect(manager.connectionStepper === stuckStepper)

		await stuckStepper.cancelCurrentlyExecutingStep(withError: nil)
		_ = await stuckRun.value
		manager.connectionStepper = nil
	}
}
