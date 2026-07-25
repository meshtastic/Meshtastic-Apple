//
//  SequentialStepsCancellationTests.swift
//  MeshtasticTests
//
//  Regression coverage for the connect state machine in
//  AccessoryManager+Connect.swift.
//
//  The bug: SequentialSteps.run()'s inner per-step retry loop treated a
//  CancellationError with no accompanying externalError as a reason to
//  `break stepRetryLoop`. Breaking out of a labelled loop does not throw, so the
//  enclosing `do` completed normally, the outer failure handler never ran, and the
//  machine advanced to the next step as if the cancelled step had succeeded.
//
//  Only `.retryStep` steps could reach that branch: every `.retryAll` step has
//  stepRetries == 1, so stepRetryAttempt is always the last attempt and the error is
//  rethrown before the switch. Step 5 (sendWantDatabase) is the only `.retryStep`
//  step in the connect pipeline, and it is the one that parks on a cancellable
//  continuation, so a teardown that resumes that continuation (closeConnection()
//  called outside cancelCurrentlyExecutingStep) pushed the machine into Step 5a,
//  which waited on a gate that closeConnection() had just reset and, before this
//  change, had no timeout. connect() then never returned and connectionStepper was
//  never cleared, leaving a zombie machine that a later connect could resume.
//

import Foundation
import MeshtasticProtobufs
import Testing

@testable import Meshtastic

/// Records the order in which pipeline steps began executing.
actor StepExecutionRecorder {
	private(set) var startedSteps: [Int] = []

	func recordStart(_ step: Int) {
		startedSteps.append(step)
	}
}

@Suite("SequentialSteps cancellation handling")
struct SequentialStepsCancellationTests {

	/// Polls `condition` until it is true or the budget runs out. Returns whether it
	/// became true. Used instead of a fixed sleep so these tests do not depend on how
	/// quickly the actor schedules each step.
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

	/// `AccessoryError` is not Equatable, so match the case rather than comparing values.
	private func isTooManyRetries(_ error: Error?) -> Bool {
		guard let accessoryError = error as? AccessoryError else { return false }
		if case .tooManyRetries = accessoryError { return true }
		return false
	}

	/// The core regression: a `.retryStep` step cancelled mid-flight, with no external
	/// error recorded, must not let the machine continue to the following step.
	@Test func cancelledRetryStepDoesNotAdvanceToTheNextStep() async {
		let recorder = StepExecutionRecorder()

		// Mirrors Step 5 / Step 5a: a `.retryStep` step with a timeout that parks on a
		// cancellable suspension, followed by a step that must not run if it is cancelled.
		let stepper = SequentialSteps(maxRetries: 1, retryDelay: .milliseconds(10)) {
			Step(timeout: .seconds(10), onFailure: .retryStep(attempts: 3)) { _ in
				await recorder.recordStart(0)
				try await Task.sleep(for: .seconds(30))
			}
			Step { _ in
				await recorder.recordStart(1)
			}
		}

		let runTask = Task { try await stepper.run() }

		let started = await waitUntil { await recorder.startedSteps == [0] }
		#expect(started)

		// The teardown path this models (closeConnection() resuming the wantDatabase
		// continuation) never records an external error, so pass nil here.
		await stepper.cancelCurrentlyExecutingStep(withError: nil)

		var runError: Error?
		do {
			try await runTask.value
		} catch {
			runError = error
		}

		// A cancelled step is a failed step: run() must report failure. maxRetries is 1, so the
		// outer handler's `continue retryLoop` exhausts the attempt loop and run() ends in
		// tooManyRetries. Asserting the case (not just non-nil) pins that the cancellation reached
		// the outer failure handler instead of some other throw ending the run.
		#expect(isTooManyRetries(runError))
		// ...and the step after it must never have been entered.
		#expect(await recorder.startedSteps == [0])
		#expect(await stepper.isRunning == false)
	}

	/// The external-error substitution that the cancellation branch already performed
	/// still has to work: the recorded error replaces the bare CancellationError, is
	/// consumed, and the machine still does not advance.
	@Test func cancelledRetryStepWithExternalErrorAlsoDoesNotAdvance() async {
		let recorder = StepExecutionRecorder()

		let stepper = SequentialSteps(maxRetries: 1, retryDelay: .milliseconds(10)) {
			Step(timeout: .seconds(10), onFailure: .retryStep(attempts: 3)) { _ in
				await recorder.recordStart(0)
				try await Task.sleep(for: .seconds(30))
			}
			Step { _ in
				await recorder.recordStart(1)
			}
		}

		let runTask = Task { try await stepper.run() }
		#expect(await waitUntil { await recorder.startedSteps == [0] })

		await stepper.cancelCurrentlyExecutingStep(withError: AccessoryError.ioFailed("link dropped"))

		var runError: Error?
		do {
			try await runTask.value
		} catch {
			runError = error
		}

		#expect(isTooManyRetries(runError))
		#expect(await recorder.startedSteps == [0])
		let leftoverExternalError = await stepper.externalError
		#expect(leftoverExternalError == nil)
	}

	/// A non-cancellation failure on a `.retryStep` step still retries that step in
	/// place, so the cancellation fix must not have collapsed the retry behaviour.
	@Test func failingRetryStepStillRetriesInPlace() async {
		let recorder = StepExecutionRecorder()

		let stepper = SequentialSteps(maxRetries: 1, retryDelay: .milliseconds(10)) {
			Step(onFailure: .retryStep(attempts: 3)) { _ in
				let attempts = await recorder.startedSteps.count
				await recorder.recordStart(0)
				if attempts < 2 {
					throw AccessoryError.ioFailed("transient")
				}
			}
			Step { _ in
				await recorder.recordStart(1)
			}
		}

		// Step 0 succeeds on its third in-place attempt, so the whole run has to complete cleanly.
		do {
			try await stepper.run()
		} catch {
			Issue.record("run() should have completed without throwing, got \(error)")
		}

		#expect(await recorder.startedSteps == [0, 0, 0, 1])
	}

	/// isRunning is read by AccessoryManager.didReceive() to decide whether to move the
	/// UI to `.discovering`. The retry sleep at the top of the step loop sits outside
	/// the per-step `do`, so a throw from there used to leave isRunning stuck at true.
	@Test func isRunningClearsWhenRunThrowsFromTheRetryDelay() async {
		let stepper = SequentialSteps(maxRetries: 3, retryDelay: .seconds(30)) {
			Step { _ in
				throw AccessoryError.ioFailed("always fails")
			}
		}

		let runTask = Task { try await stepper.run() }

		// The first attempt fails immediately, so the machine is parked in the retry
		// sleep ahead of attempt 2 by the time isRunning has been observed as true.
		#expect(await waitUntil { await stepper.isRunning })
		try? await Task.sleep(for: .milliseconds(100))

		// Cancelling the task that called run() throws out of that sleep.
		runTask.cancel()
		_ = try? await runTask.value

		#expect(await stepper.isRunning == false)
	}
}
