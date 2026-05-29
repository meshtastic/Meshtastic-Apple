// AsyncConcurrencyTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

// MARK: - AsyncGate Tests

@Suite("AsyncGate")
struct AsyncGateTests {

	@Test func openGate_resumesWaiters() async throws {
		let gate = AsyncGate()
		// Open then wait should return immediately
		await gate.open()
		try await gate.wait()
	}

	@Test func wait_afterOpen_returnsImmediately() async throws {
		let gate = AsyncGate()
		await gate.open()
		try await gate.wait()
		// If we get here, the gate was open
	}

	@Test func reset_closesGate() async throws {
		let gate = AsyncGate()
		await gate.open()
		await gate.reset()
		// Gate is now closed, waiting should suspend
		// We test this indirectly by opening from another task
		let expectation = LockedBox(false)
		let waitTask = Task {
			try await gate.wait()
			await expectation.set(true)
		}
		// Give the wait a moment to suspend
		try await Task.sleep(for: .milliseconds(50))
		let beforeOpen = await expectation.get()
		#expect(beforeOpen == false)
		await gate.open()
		try await waitTask.value
		let afterOpen = await expectation.get()
		#expect(afterOpen == true)
	}

	@Test func cancelAll_throwsCancellationError() async {
		let gate = AsyncGate()
		let waitTask = Task {
			try await gate.wait()
		}
		try? await Task.sleep(for: .milliseconds(50))
		await gate.cancelAll()
		do {
			try await waitTask.value
			Issue.record("Expected CancellationError")
		} catch {
			#expect(error is CancellationError)
		}
	}

	@Test func throwAll_throwsCustomError() async {
		let gate = AsyncGate()
		struct TestError: Error {}
		let waitTask = Task {
			try await gate.wait()
		}
		try? await Task.sleep(for: .milliseconds(50))
		await gate.throwAll(TestError())
		do {
			try await waitTask.value
			Issue.record("Expected TestError")
		} catch {
			#expect(error is TestError)
		}
	}

	@Test func fail_isAliasForThrowAll() async {
		let gate = AsyncGate()
		struct FailError: Error {}
		let waitTask = Task {
			try await gate.wait()
		}
		try? await Task.sleep(for: .milliseconds(50))
		await gate.fail(FailError())
		do {
			try await waitTask.value
			Issue.record("Expected FailError")
		} catch {
			#expect(error is FailError)
		}
	}

	@Test func multipleWaiters_allResumed() async throws {
		let gate = AsyncGate()
		let count = LockedBox(0)

		let tasks = (0..<5).map { _ in
			Task {
				try await gate.wait()
				await count.increment()
			}
		}
		try await Task.sleep(for: .milliseconds(50))
		await gate.open()

		for task in tasks {
			try await task.value
		}
		let finalCount = await count.get()
		#expect(finalCount == 5)
	}
}

// MARK: - ResettableTimer Tests

@Suite("ResettableTimer")
struct ResettableTimerTests {

	@Test func oneShotTimer_fires() async throws {
		let fired = LockedBox(false)
		let timer = ResettableTimer {
			await fired.set(true)
		}
		await timer.reset(delay: .milliseconds(100))
		try await Task.sleep(for: .milliseconds(1000))
		let result = await fired.get()
		#expect(result == true)
	}

	@Test func cancel_preventsFiring() async throws {
		let fired = LockedBox(false)
		let timer = ResettableTimer {
			await fired.set(true)
		}
		await timer.reset(delay: .milliseconds(100))
		await timer.cancel()
		try await Task.sleep(for: .milliseconds(200))
		let result = await fired.get()
		#expect(result == false)
	}

	@Test func reset_restartsDelay() async throws {
		let count = LockedBox(0)
		let timer = ResettableTimer {
			await count.increment()
		}
		await timer.reset(delay: .milliseconds(500))
		try await Task.sleep(for: .milliseconds(100))
		// Reset before first fire - should restart the 500ms delay
		await timer.reset(delay: .milliseconds(500))
		try await Task.sleep(for: .milliseconds(200))
		let midCount = await count.get()
		#expect(midCount == 0, "Timer should not have fired yet after reset")
		try await Task.sleep(for: .milliseconds(1000))
		let finalCount = await count.get()
		#expect(finalCount == 1)
		await timer.cancel()
	}

	@Test func repeatingTimer_firesMultipleTimes() async throws {
		let count = LockedBox(0)
		let timer = ResettableTimer(isRepeating: true) {
			await count.increment()
		}
		await timer.reset(delay: .milliseconds(100))
		try await Task.sleep(for: .milliseconds(2000))
		await timer.cancel()
		let finalCount = await count.get()
		#expect(finalCount >= 2, "Expected repeating timer to fire at least twice, got \(finalCount)")
	}

	@Test func cancelWithReason_stopsTimer() async throws {
		let fired = LockedBox(false)
		let timer = ResettableTimer(debugName: "TestTimer") {
			await fired.set(true)
		}
		await timer.reset(delay: .milliseconds(100), withReason: "starting")
		await timer.cancel(withReason: "testing cancel")
		try await Task.sleep(for: .milliseconds(200))
		let result = await fired.get()
		#expect(result == false)
	}
}

// MARK: - Thread-safe helper for async tests

actor LockedBox<T: Sendable> {
	private var value: T

	init(_ value: T) {
		self.value = value
	}

	func get() -> T { value }

	func set(_ newValue: T) {
		value = newValue
	}

	func increment() where T == Int {
		value += 1
	}
}
