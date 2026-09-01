import SwiftData
import Testing
import UIKit

@testable import Meshtastic

@Suite("Persistence controller bootstrap", .serialized)
@MainActor
struct PersistenceControllerBootstrapTests {

	private enum TestError: Error {
		case failed
	}

	@Test("The shared controller is ready in the test host")
	func sharedControllerIsReadyForTests() {
		#expect(PersistenceController.shared.state == .ready)
		_ = PersistenceController.shared.context
	}

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(
			"PersistenceControllerBootstrapTests",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return try ModelContainer(for: schema, configurations: configuration)
	}

	@Test("Concurrent callers share one startup task")
	func concurrentCallersShareStartup() async throws {
		var loadCount = 0
		let controller = PersistenceController {
			loadCount += 1
			try await Task.sleep(for: .milliseconds(50))
			return try makeContainer()
		}

		async let first = controller.ready()
		async let second = controller.ready()
		let controllers = try await [first, second]

		#expect(loadCount == 1)
		#expect(controllers.allSatisfy { $0 === controller })
		#expect(controller.state == .ready)
	}

	@Test("A failed startup publishes no ready state and Retry starts again")
	func failureCanRetry() async throws {
		var attempts = 0
		let controller = PersistenceController {
			attempts += 1
			if attempts == 1 {
				throw TestError.failed
			}
			return try makeContainer()
		}

		await #expect(throws: PersistenceController.ReadinessError.self) {
			try await controller.ready()
		}
		guard case .failed = controller.state else {
			Issue.record("Expected failed state")
			return
		}

		await controller.retry()

		#expect(attempts == 2)
		#expect(controller.state == .ready)
	}

	@Test("Concurrent failures are normalized and Retry starts a new task")
	func concurrentFailureCanRetry() async {
		var attempts = 0
		let controller = PersistenceController {
			attempts += 1
			try await Task.sleep(for: .milliseconds(50))
			if attempts == 1 {
				throw TestError.failed
			}
			return try makeContainer()
		}

		let first = Task { @MainActor in
			do {
				_ = try await controller.ready()
				return false
			} catch is PersistenceController.ReadinessError {
				return true
			} catch {
				return false
			}
		}
		let second = Task { @MainActor in
			do {
				_ = try await controller.ready()
				return false
			} catch is PersistenceController.ReadinessError {
				return true
			} catch {
				return false
			}
		}

		#expect(await first.value)
		#expect(await second.value)
		#expect(attempts == 1)
		guard case .failed = controller.state else {
			Issue.record("Expected failed state")
			return
		}

		await controller.retry()
		#expect(attempts == 2)
		#expect(controller.state == .ready)
	}

	@Test("Retry starts after failure is published before callers are collected")
	func retryAfterPublishedFailure() async {
		var attempts = 0
		let controller = PersistenceController {
			attempts += 1
			if attempts == 1 {
				throw TestError.failed
			}
			return try makeContainer()
		}
		let first = Task { try? await controller.ready() }
		let second = Task { try? await controller.ready() }

		while true {
			if case .failed = controller.state { break }
			await Task.yield()
		}
		await controller.retry()

		_ = await first.value
		_ = await second.value
		#expect(attempts == 2)
		#expect(controller.state == .ready)
	}

	@Test("The controller stays unpublished while startup is running")
	func controllerIsNotReadyDuringStartup() async throws {
		let controller = PersistenceController {
			try await Task.sleep(for: .milliseconds(100))
			return try makeContainer()
		}
		let startup = Task { try await controller.ready() }

		while controller.state == .idle {
			await Task.yield()
		}
		#expect(controller.state == .preparing)

		_ = try await startup.value
		#expect(controller.state == .ready)
	}

	@Test("Canceling a protected-data waiter removes its continuation")
	func cancelingProtectedDataWaiter() async {
		let controller = PersistenceController(
			startupLoader: { try makeContainer() },
			protectedDataAvailable: { false }
		)
		let waiter = Task { try await controller.waitUntilReady() }

		while controller.protectedDataWaiterCountForTesting == 0 {
			await Task.yield()
		}
		waiter.cancel()
		await #expect(throws: CancellationError.self) {
			try await waiter.value
		}
		#expect(controller.protectedDataWaiterCountForTesting == 0)
	}

	@Test("Cancel and unlock resume a waiter once")
	func cancelUnlockRace() async {
		var protectedDataAvailable = false
		let controller = PersistenceController(
			startupLoader: { try makeContainer() },
			protectedDataAvailable: { protectedDataAvailable }
		)
		let waiter = Task { try await controller.waitUntilReady() }

		while controller.protectedDataWaiterCountForTesting == 0 {
			await Task.yield()
		}
		waiter.cancel()
		protectedDataAvailable = true
		NotificationCenter.default.post(
			name: UIApplication.protectedDataDidBecomeAvailableNotification,
			object: nil
		)
		_ = try? await waiter.value

		#expect(controller.protectedDataWaiterCountForTesting == 0)
	}

	@Test("An unlock during observer installation restarts startup")
	func unlockDuringObserverInstallation() async throws {
		var availabilityChecks = 0
		var loadCount = 0
		let controller = PersistenceController(
			startupLoader: {
				loadCount += 1
				return try makeContainer()
			},
			protectedDataAvailable: {
				availabilityChecks += 1
				return availabilityChecks > 1
			}
		)

		_ = try await controller.waitUntilReady()

		#expect(loadCount == 1)
		#expect(controller.state == .ready)
	}

	@Test("A cold-launch caller waits for unlock without publishing a container")
	func waitsForProtectedData() async throws {
		var protectedDataAvailable = false
		var loadCount = 0
		let controller = PersistenceController(
			startupLoader: {
				loadCount += 1
				return try makeContainer()
			},
			protectedDataAvailable: { protectedDataAvailable }
		)
		let restoration = Task { try await controller.waitUntilReady() }

		while controller.state == .idle {
			await Task.yield()
		}
		#expect(controller.state == .waitingForProtectedData)
		#expect(loadCount == 0)
		await #expect(throws: PersistenceController.ReadinessError.self) {
			try await controller.ready()
		}

		protectedDataAvailable = true
		NotificationCenter.default.post(
			name: UIApplication.protectedDataDidBecomeAvailableNotification,
			object: nil
		)
		_ = try await restoration.value

		#expect(loadCount == 1)
		#expect(controller.state == .ready)
	}
}
