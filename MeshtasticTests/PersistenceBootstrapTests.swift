import XCTest
@testable import Meshtastic

@MainActor
final class PersistenceBootstrapTests: XCTestCase {
	func testStartPublishesPreparingBeforeReady() async throws {
		let bootstrap = PersistenceBootstrap(loader: {
			try await Task.sleep(for: .milliseconds(20))
			return PersistenceController(inMemory: true)
		})

		let start = Task { await bootstrap.start() }
		await Task.yield()
		XCTAssertEqual(bootstrap.state, .preparing)

		await start.value
		XCTAssertEqual(bootstrap.state, .ready)
		XCTAssertNotNil(bootstrap.persistenceController)
	}

	func testReadyControllerWaitsForAnActiveStart() async {
		let bootstrap = PersistenceBootstrap(loader: {
			try await Task.sleep(for: .milliseconds(20))
			return PersistenceController(inMemory: true)
		})

		let start = Task { await bootstrap.start() }
		await Task.yield()
		let controller = await bootstrap.readyController()

		await start.value
		XCTAssertNotNil(controller)
		XCTAssertTrue(controller === bootstrap.persistenceController)
		XCTAssertEqual(bootstrap.state, .ready)
	}

	func testMultipleReadyWaitersShareOneStart() async {
		var loadCount = 0
		let bootstrap = PersistenceBootstrap(loader: {
			loadCount += 1
			try await Task.sleep(for: .milliseconds(20))
			return PersistenceController(inMemory: true)
		})

		let first = Task { await bootstrap.readyController() }
		let second = Task { await bootstrap.readyController() }
		let third = Task { await bootstrap.readyController() }
		let controllers = await [first.value, second.value, third.value]

		XCTAssertEqual(loadCount, 1)
		XCTAssertTrue(controllers.allSatisfy { $0 === bootstrap.persistenceController })
	}

	func testReadyWaiterResumesAfterProtectedDataBecomesAvailable() async {
		var isUnavailable = true
		let bootstrap = PersistenceBootstrap(
			protectedDataUnavailable: { isUnavailable },
			loader: { PersistenceController(inMemory: true) }
		)

		let waiter = Task { await bootstrap.waitUntilReady() }
		await Task.yield()
		XCTAssertEqual(bootstrap.state, .waitingForProtectedData)

		isUnavailable = false
		await bootstrap.start()

		let didBecomeReady = await waiter.value
		XCTAssertTrue(didBecomeReady)
		XCTAssertEqual(bootstrap.state, .ready)
	}

	func testReadyWaiterResumesAfterProtectedDataRecoveryFails() async {
		var isUnavailable = true
		let bootstrap = PersistenceBootstrap(
			protectedDataUnavailable: { isUnavailable },
			loader: { throw BootstrapTestError.failed }
		)

		let waiter = Task { await bootstrap.waitUntilReady() }
		await Task.yield()
		XCTAssertEqual(bootstrap.state, .waitingForProtectedData)

		isUnavailable = false
		await bootstrap.start()

		let didBecomeReady = await waiter.value
		XCTAssertFalse(didBecomeReady)
		guard case .failed = bootstrap.state else {
			return XCTFail("Expected protected-data recovery to publish failure")
		}
	}

	func testProtectedDataDoesNotPublishReadyUntilAvailable() async {
		var isUnavailable = true
		var loadCount = 0
		let bootstrap = PersistenceBootstrap(
			protectedDataUnavailable: { isUnavailable },
			loader: {
				loadCount += 1
				return PersistenceController(inMemory: true)
			}
		)

		await bootstrap.start()
		XCTAssertEqual(bootstrap.state, .waitingForProtectedData)
		XCTAssertNil(bootstrap.persistenceController)
		XCTAssertEqual(loadCount, 0)

		isUnavailable = false
		await bootstrap.start()
		XCTAssertEqual(bootstrap.state, .ready)
		XCTAssertNotNil(bootstrap.persistenceController)
		XCTAssertEqual(loadCount, 1)
	}

	func testRetryRunsLoaderAgainAfterFailure() async {
		var attempts = 0
		let bootstrap = PersistenceBootstrap(loader: {
			attempts += 1
			if attempts == 1 {
				throw BootstrapTestError.failed
			}
			return PersistenceController(inMemory: true)
		})

		await bootstrap.start()
		guard case .failed = bootstrap.state else {
			return XCTFail("Expected the first attempt to fail")
		}

		await bootstrap.retry()
		XCTAssertEqual(attempts, 2)
		XCTAssertEqual(bootstrap.state, .ready)
	}

	func testIdleTimerIsDisabledDuringOperationAndRestoredAfterSuccess() async {
		var isDisabled = false
		var transitions = [Bool]()

		let result = await PersistenceBootstrap.withIdleTimerDisabled(
			getValue: { isDisabled },
			setValue: {
				isDisabled = $0
				transitions.append($0)
			}
		) {
			XCTAssertTrue(isDisabled)
			return 42
		}

		XCTAssertEqual(result, 42)
		XCTAssertFalse(isDisabled)
		XCTAssertEqual(transitions, [true, false])
	}

	func testIdleTimerPreservesPreviouslyDisabledValue() async {
		var isDisabled = true

		await PersistenceBootstrap.withIdleTimerDisabled(
			getValue: { isDisabled },
			setValue: { isDisabled = $0 }
		) {
			XCTAssertTrue(isDisabled)
		}

		XCTAssertTrue(isDisabled)
	}

	func testIdleTimerIsRestoredAfterFailure() async {
		var isDisabled = false

		do {
			try await PersistenceBootstrap.withIdleTimerDisabled(
				getValue: { isDisabled },
				setValue: { isDisabled = $0 }
			) {
				XCTAssertTrue(isDisabled)
				throw BootstrapTestError.failed
			}
			XCTFail("Expected the operation to fail")
		} catch BootstrapTestError.failed {
			XCTAssertFalse(isDisabled)
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}
}

private enum BootstrapTestError: Error {
	case failed
}
