import Combine
import Foundation
import OSLog
import UIKit

@MainActor
final class PersistenceBootstrap: ObservableObject {
	static let shared = PersistenceBootstrap()

	enum State: Equatable {
		case waiting
		case waitingForProtectedData
		case preparing
		case migrating
		case ready
		case failed(String)
	}

	typealias Loader = @MainActor () async throws -> PersistenceController
	typealias ProtectedDataUnavailable = @MainActor () -> Bool

	@Published private(set) var state: State = .waiting
	private(set) var persistenceController: PersistenceController?

	private let loader: Loader?
	private let protectedDataUnavailable: ProtectedDataUnavailable
	private var protectedDataObserver: NSObjectProtocol?
	private var isRunning = false
	private var startupWaiters: [CheckedContinuation<Void, Never>] = []
	private var readinessWaiters: [CheckedContinuation<Bool, Never>] = []

	init(
		protectedDataUnavailable: ProtectedDataUnavailable? = nil,
		loader: Loader? = nil
	) {
		self.loader = loader
		self.protectedDataUnavailable = protectedDataUnavailable ?? {
			Self.protectedStoreIsUnavailable()
		}
	}

	func start() async {
		guard state != .ready else { return }
		if isRunning {
			await withCheckedContinuation { continuation in
				startupWaiters.append(continuation)
			}
			return
		}
		isRunning = true
		defer {
			isRunning = false
			resolveReadinessWaitersIfTerminal()
			let waiters = startupWaiters
			startupWaiters.removeAll()
			for waiter in waiters {
				waiter.resume()
			}
		}

		guard !protectedDataUnavailable() else {
			state = .waitingForProtectedData
			observeProtectedDataAvailabilityIfNeeded()
			return
		}
		state = .preparing

		do {
			let controller: PersistenceController
			if let loader {
				controller = try await loader()
			} else {
				try CoreDataMigrationService.prepareForMigration()
				controller = persistenceController ?? PersistenceController.shared
				persistenceController = controller
				let legacyStoreExists = CoreDataMigrationService.legacyStoreExists()
				if legacyStoreExists && !controller.isProvisionalPendingFirstUnlock {
					state = .migrating
					try await Self.withIdleTimerDisabled {
						try await CoreDataMigrationService.migrateOffMain(into: controller.container)
					}
				}
			}
			persistenceController = controller
			guard !controller.isProvisionalPendingFirstUnlock else {
				state = .waitingForProtectedData
				observeProtectedDataAvailabilityIfNeeded()
				return
			}
			state = .ready
		} catch {
			Logger.data.error("⬆️ Persistence bootstrap failed: \(error.localizedDescription, privacy: .public)")
			state = .failed(error.localizedDescription)
		}
	}

	func waitUntilReady() async -> Bool {
		await start()
		switch state {
		case .ready:
			return true
		case .failed:
			return false
		case .waitingForProtectedData:
			return await withCheckedContinuation { continuation in
				readinessWaiters.append(continuation)
			}
		case .waiting, .preparing, .migrating:
			return false
		}
	}

	func readyController() async -> PersistenceController? {
		guard await waitUntilReady() else { return nil }
		return persistenceController
	}

	func retry() async {
		guard case .failed = state else { return }
		await start()
	}

	static func withIdleTimerDisabled<T>(
		getValue: @MainActor () -> Bool = { UIApplication.shared.isIdleTimerDisabled },
		setValue: @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 },
		operation: @MainActor () async throws -> T
	) async rethrows -> T {
		let previousValue = getValue()
		setValue(true)
		defer { setValue(previousValue) }
		return try await operation()
	}

	static func protectedStoreIsUnavailable(
		locations: CoreDataMigrationService.StoreLocations = .applicationSupport
	) -> Bool {
		[
			locations.candidateStoreURL,
			locations.legacyStoreURL,
			locations.destinationStoreURL
		].contains(where: PersistenceController.storeExistsButIsUnreadable)
	}

	private func resolveReadinessWaitersIfTerminal() {
		let result: Bool
		switch state {
		case .ready:
			result = true
		case .failed:
			result = false
		case .waiting, .waitingForProtectedData, .preparing, .migrating:
			return
		}
		let waiters = readinessWaiters
		readinessWaiters.removeAll()
		for waiter in waiters {
			waiter.resume(returning: result)
		}
	}

	private func observeProtectedDataAvailabilityIfNeeded() {
		guard loader == nil, protectedDataObserver == nil else { return }
		protectedDataObserver = NotificationCenter.default.addObserver(
			forName: UIApplication.protectedDataDidBecomeAvailableNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				if let observer = self.protectedDataObserver {
					NotificationCenter.default.removeObserver(observer)
					self.protectedDataObserver = nil
				}
				Task {
					await Task.yield()
					await self.start()
				}
			}
		}
	}
}
