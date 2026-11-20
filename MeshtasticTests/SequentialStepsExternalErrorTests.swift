//
//  SequentialStepsExternalErrorTests.swift
//  MeshtasticTests
//
//  A connection error reported while a connect step runs has to fail that attempt, even when
//  the step itself finishes instead of throwing on cancellation. Before this, the process went
//  on to the remaining steps and ended "Subscribed" on a link that had already dropped.
//

import Foundation
import Testing

@testable import Meshtastic

private actor StepLog {
	private(set) var entries: [String] = []

	func add(_ entry: String) {
		entries.append(entry)
	}
}

/// Lets a step reach the stepper that runs it, the way a connection event reaches it in the app.
private final class StepperBox: @unchecked Sendable {
	var stepper: SequentialSteps?
}

private struct LinkLost: Error {}

@Suite(.timeLimit(.minutes(1)))
struct SequentialStepsExternalErrorTests {

	@Test func errorDuringStepThatIgnoresCancellationRetriesTheAttempt() async throws {
		let log = StepLog()
		let box = StepperBox()
		let stepper = SequentialSteps(maxRetries: 3, retryDelay: .milliseconds(1)) {
			Step { attempt in
				await log.add("\(attempt):connect")
			}
			Step { attempt in
				await log.add("\(attempt):sendTime")
				if attempt == 0 {
					// The link drops mid-step; this step carries on regardless.
					await box.stepper?.cancelCurrentlyExecutingStep(withError: LinkLost())
				}
			}
			Step { attempt in
				await log.add("\(attempt):finish")
			}
		}
		box.stepper = stepper

		try await stepper.run()

		#expect(await log.entries == [
			"0:connect", "0:sendTime",
			"1:connect", "1:sendTime", "1:finish"
		])
	}

	/// The fix leaves the error set for a cancelled process: clearing it made run() throw
	/// CancellationError instead of the link error. Before the fix, a process that stopped
	/// this way also stayed marked as running, so it took a later error and dropped it.
	@Test func errorThatEndsTheProcessStopsBeforeTheNextStep() async throws {
		let log = StepLog()
		let box = StepperBox()
		let stepper = SequentialSteps(maxRetries: 3, retryDelay: .milliseconds(1)) {
			Step { attempt in
				await log.add("\(attempt):sendTime")
				await box.stepper?.cancelCurrentlyExecutingStep(withError: LinkLost(), cancelFullProcess: true)
			}
			Step { attempt in
				await log.add("\(attempt):finish")
			}
		}
		box.stepper = stepper

		await #expect(throws: LinkLost.self) {
			try await stepper.run()
		}
		#expect(await log.entries == ["0:sendTime"])
		#expect(await stepper.isRunning == false)
		#expect(await stepper.cancelCurrentlyExecutingStep(withError: LinkLost()) == false)
	}

	/// On the last attempt, with no step after it, the link error still ends the process
	/// rather than tooManyRetries.
	@Test func errorThatEndsTheProcessOnTheLastAttemptKeepsItsError() async throws {
		let box = StepperBox()
		let stepper = SequentialSteps(maxRetries: 1, retryDelay: .milliseconds(1)) {
			Step { _ in
				await box.stepper?.cancelCurrentlyExecutingStep(withError: LinkLost(), cancelFullProcess: true)
			}
		}
		box.stepper = stepper

		await #expect(throws: LinkLost.self) {
			try await stepper.run()
		}
		#expect(await stepper.isRunning == false)
	}

	@Test func finishedStepperRefusesTheError() async throws {
		let stepper = SequentialSteps(maxRetries: 1, retryDelay: .milliseconds(1)) {
			Step { _ in }
		}
		try await stepper.run()

		#expect(await stepper.cancelCurrentlyExecutingStep(withError: LinkLost()) == false)
		#expect(await stepper.isRunning == false)
	}

	@Test func failedStepperRefusesALaterError() async {
		let stepper = SequentialSteps(maxRetries: 3, retryDelay: .milliseconds(1)) {
			Step(onFailure: .fail) { _ in
				throw LinkLost()
			}
		}

		await #expect(throws: LinkLost.self) {
			try await stepper.run()
		}
		#expect(await stepper.isRunning == false)
		#expect(await stepper.cancelCurrentlyExecutingStep(withError: LinkLost()) == false)
	}

	@Test func runningStepperAcceptsTheError() async throws {
		let accepted = StepLog()
		let box = StepperBox()
		let stepper = SequentialSteps(maxRetries: 2, retryDelay: .milliseconds(1)) {
			Step { attempt in
				if attempt == 0, let stepper = box.stepper {
					let result = await stepper.cancelCurrentlyExecutingStep(withError: LinkLost())
					await accepted.add("\(result)")
				}
			}
		}
		box.stepper = stepper

		try await stepper.run()

		#expect(await accepted.entries == ["true"])
	}
}
