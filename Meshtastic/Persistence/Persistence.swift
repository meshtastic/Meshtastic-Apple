//
//  Persistence.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/28/21.
//

import SwiftData
import OSLog
import Foundation
import UIKit
import Combine

@MainActor
final class PersistenceController: ObservableObject {

	enum State: Equatable {
		case idle
		case waitingForProtectedData
		case preparing
		case migrating
		case ready
		case failed(String)
	}

	enum ReadinessError: LocalizedError {
		case protectedDataUnavailable
		case startupFailed(String)

		var errorDescription: String? {
			switch self {
			case .protectedDataUnavailable:
				return "Protected data is unavailable"
			case .startupFailed(let message):
				return message
			}
		}
	}

	static let shared: PersistenceController = {
		let isTestEnvironment = NSClassFromString("XCTestCase") != nil
			|| ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
		if isTestEnvironment {
			return PersistenceController(inMemory: true, storeName: "MeshtasticTests")
		}
		return PersistenceController(deferred: true)
	}()

	static var preview: PersistenceController = {
		let result = PersistenceController(inMemory: true, storeName: "MeshtasticPreview")
		let context = result.container.mainContext
		for _ in 0..<10 {
			let newItem = NodeInfoEntity()
			newItem.lastHeard = Date()
			context.insert(newItem)
		}
		return result
	}()

	@Published private(set) var state: State

	typealias StartupLoader = @MainActor () async throws -> ModelContainer
	typealias ProtectedDataAvailability = @MainActor () -> Bool

	private var readyContainer: ModelContainer?
	private var startupTask: Task<PersistenceController, Error>?
	private var protectedDataObserver: NSObjectProtocol?
	private var protectedDataWaiters = [UUID: CheckedContinuation<Void, Error>]()
	private let startupLoader: StartupLoader?
	private let protectedDataAvailable: ProtectedDataAvailability

	var container: ModelContainer {
		guard state == .ready, let readyContainer else {
			preconditionFailure("PersistenceController.ready() must succeed before accessing the container")
		}
		return readyContainer
	}

	/// Advances synchronously with each container replacement. Long-lived view tasks capture the
	/// generation they were mounted against and stop before touching a stale `ModelContext`.
	private(set) var containerGeneration = 0

	/// Remembered so the store can be reopened in a fresh container — see `recreateContainer()`.
	private let storeName: String
	private let inMemory: Bool

	var context: ModelContext {
		container.mainContext
	}

	/// Distinguishes "the store file is locked by data protection" from "the store file is corrupt".
	/// Before the first unlock, `open(2)` on a file protected with the default
	/// CompleteUntilFirstUserAuthentication class fails outright; a corrupt-but-unlocked file opens
	/// fine at the POSIX layer (its damage surfaces inside SQLite instead). Any exists-but-unopenable
	/// state is treated as locked: the cost of a false positive is delayed startup, while
	/// destructive "recovery" of a merely-locked store permanently deletes the user's data (#2243).
	nonisolated static func storeExistsButIsUnreadable(at url: URL) -> Bool {
		guard FileManager.default.fileExists(atPath: url.path) else { return false }
		let fd = open(url.path, O_RDONLY)
		if fd >= 0 {
			close(fd)
			return false
		}
		return true
	}

	/// Reopen the (already-migrated) store in a brand-new `ModelContainer`, replacing `container`.
	///
	/// Used after a full data clear so every context — the main context and any actor contexts
	/// built from the container — starts with no stale object registrations. Without this, a
	/// long-lived context keeps the pre-clear objects registered; on reconnect SQLite reuses the
	/// freed rowids, so a fetch/relationship access returns a dead instance and SwiftData traps
	/// with "This model instance was destroyed by calling ModelContext.reset".
	///
	/// Invariant: any caller that can run while the UI is in the FOREGROUND must also bump
	/// `AppState.databaseResetID` after this returns. The swap advances `containerGeneration`,
	/// which makes guarded view tasks (e.g. the Nodes refresh loop) stop fetching; only the
	/// `.id(databaseResetID)` remount re-binds them to the new container. A foreground caller
	/// that forgets the bump gets a silently frozen list, not a crash.
	func recreateContainer() {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			storeName,
			schema: schema,
			isStoredInMemoryOnly: inMemory,
			allowsSave: true
		)
		do {
			// Mirror init()'s open logic: on-disk stores go through the migration plan so a
			// reopen behaves identically to launch if a schema migration ever applies here.
			let fresh: ModelContainer
			if inMemory {
				fresh = try ModelContainer(for: schema, configurations: config)
			} else {
				fresh = try ModelContainer(for: schema, migrationPlan: MeshtasticMigrationPlan.self, configurations: config)
			}
			fresh.mainContext.autosaveEnabled = false
			containerGeneration &+= 1
			readyContainer = fresh
			Logger.data.info("💾 SwiftData container recreated after data clear")
		} catch {
			Logger.data.error("💾 Failed to recreate SwiftData container: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Nuclear reset: delete the on-disk store files and reopen a brand-new, guaranteed-empty
	/// container. Used by the device-switch / cross-device reset paths as an escalation when the
	/// per-model `clearDatabase` fails part-way (e.g. a relationship constraint aborts the batch
	/// deletes) — proceeding on a half-cleared store is how one radio's nodes leak into another's
	/// session. POSIX unlink semantics make this safe with stragglers: any old context still
	/// holding the previous container writes to the unlinked inode, never into the new store.
	/// Not usable when data must be preserved (routes, favorites) — everything is erased.
	func destroyStoreAndRecreateContainer() {
		guard !inMemory else {
			recreateContainer()
			return
		}
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false, allowsSave: true)
		// Park, don't unlink — a leaked previous container may still hold the store open
		// (see restoreStoreFromBackup); unlinking it live invalidates its fds and the broken
		// container traps on the next save notification in the process.
		Self.parkStoreFiles(at: config.url)
		recreateContainer()
		Logger.data.warning("💾 Store files destroyed and container recreated (escalated database reset)")
	}

	/// File-swap restore: replace the on-disk store with a copy of a backup and reopen the
	/// container on top of it. The switch path must not run SwiftData saves at all —
	/// observer bridges from previous containers survive any amount of view unmounting
	/// (registration lives until dealloc and the graph retains them), and a bulk restore
	/// save's synchronous NotificationCenter callout traps inside the stale bridge
	/// regardless of thread or of what is mounted (caught live in lldb at the restore's
	/// `save()`; the no-crash-report flavor of Datadog 324bff02). Replacing the store file
	/// and reopening posts nothing. POSIX unlink semantics keep stragglers safe, as with
	/// the destroy path above; `recreateContainer()` runs the migration plan in place on
	/// the writable copy, which also covers backups written by older schemas.
	/// Rename the store files out of the way instead of deleting them — unlinking a store a
	/// leaked container still has open trips SQLite's vnode watch, which invalidates the open
	/// fds ("database integrity compromised by API violation: vnode unlinked while in use")
	/// and breaks that container and everything observing through it. (SQLite alarms on a
	/// rename too, but the destroy path is an already-broken escalation; parking at least
	/// preserves the bytes.) Parked files are orphans from this or previous sessions;
	/// `sweepParkedStoreFiles()` removes last session's on launch.
	private static func parkStoreFiles(at storeURL: URL) {
		let fm = FileManager.default
		let tag = ".parked-\(UUID().uuidString.prefix(8))"
		for suffix in ["", "-wal", "-shm"] {
			let src = URL(fileURLWithPath: storeURL.path + suffix)
			guard fm.fileExists(atPath: src.path) else { continue }
			let dst = URL(fileURLWithPath: storeURL.path + tag + suffix)
			do {
				try fm.moveItem(at: src, to: dst)
			} catch {
				Logger.data.error("💾 Failed to park store file \(src.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
				// Fall back to unlink rather than restoring on top of a stale file.
				try? fm.removeItem(at: src)
			}
		}
	}

	/// Remove parked store files left by previous sessions' node switches. Called once at
	/// launch, when nothing can still hold them open.
	private static func sweepParkedStoreFiles(near storeURL: URL) {
		let fm = FileManager.default
		let dir = storeURL.deletingLastPathComponent()
		let prefix = storeURL.lastPathComponent + ".parked-"
		guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
		for name in names where name.hasPrefix(prefix) {
			try? fm.removeItem(at: dir.appendingPathComponent(name))
		}
	}

	private static func removeStoreFiles(at storeURL: URL) {
		let fm = FileManager.default
		let storeFiles = [
			storeURL,
			URL(fileURLWithPath: storeURL.path + "-shm"),
			URL(fileURLWithPath: storeURL.path + "-wal")
		]

		for url in storeFiles where fm.fileExists(atPath: url.path) {
			do {
				try fm.removeItem(at: url)
			} catch {
				Logger.data.error("📈 [PerfSeed] Failed to remove existing store file \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	private init(deferred: Bool) {
		precondition(deferred)
		storeName = "Meshtastic"
		inMemory = false
		state = .idle
		readyContainer = nil
		startupLoader = nil
		protectedDataAvailable = { UIApplication.shared.isProtectedDataAvailable }
	}

	init(
		startupLoader: @escaping StartupLoader,
		protectedDataAvailable: @escaping ProtectedDataAvailability = { true }
	) {
		storeName = "MeshtasticTest"
		inMemory = true
		state = .idle
		readyContainer = nil
		self.startupLoader = startupLoader
		self.protectedDataAvailable = protectedDataAvailable
	}

	@discardableResult
	func ready() async throws -> PersistenceController {
		if state == .ready {
			return self
		}
		if case .failed(let message) = state {
			throw ReadinessError.startupFailed(message)
		}
		if state == .waitingForProtectedData {
			guard protectedDataAvailable() else {
				throw ReadinessError.protectedDataUnavailable
			}
			state = .idle
		}
		if let startupTask {
			return try await startupTask.value
		}

		let task = Task { @MainActor [weak self] in
			guard let self else {
				throw CancellationError()
			}
			do {
				let controller = try await self.performStartup()
				self.startupTask = nil
				return controller
			} catch ReadinessError.protectedDataUnavailable {
				self.startupTask = nil
				self.state = .waitingForProtectedData
				self.observeProtectedDataAvailabilityIfNeeded()
				throw ReadinessError.protectedDataUnavailable
			} catch {
				self.startupTask = nil
				let message = error.localizedDescription
				self.state = .failed(message)
				Logger.data.error("⬆️ Persistence startup failed: \(message, privacy: .public)")
				throw ReadinessError.startupFailed(message)
			}
		}
		startupTask = task
		return try await task.value
	}

	func waitUntilReady() async throws -> PersistenceController {
		while true {
			do {
				return try await ready()
			} catch ReadinessError.protectedDataUnavailable {
				try await waitForProtectedData()
			}
		}
	}

	func retry() async {
		guard case .failed = state else { return }
		state = .idle
		_ = try? await ready()
	}

	private func performStartup() async throws -> PersistenceController {
		guard protectedDataAvailable() else {
			throw ReadinessError.protectedDataUnavailable
		}

		if let startupLoader {
			state = .preparing
			readyContainer = try await startupLoader()
			state = .ready
			return self
		}

		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			storeName,
			schema: schema,
			isStoredInMemoryOnly: false,
			allowsSave: true
		)
		guard !Self.storeExistsButIsUnreadable(at: config.url),
			  !CoreDataMigrationService.protectedStoreIsUnavailable() else {
			throw ReadinessError.protectedDataUnavailable
		}

		state = .preparing
		await Task.detached(priority: .userInitiated) {
			CoreDataMigrationService.prepareForMigration()
		}.value

		let loadedContainer = try Self.makeContainer(
			inMemory: false,
			storeName: storeName
		)

		if CoreDataMigrationService.legacyStoreExists() {
			state = .migrating
			try await CoreDataMigrationService.migrateOffMain(into: loadedContainer)
		}

		readyContainer = loadedContainer
		state = .ready
		return self
	}

	private func waitForProtectedData() async throws {
		guard !protectedDataAvailable() else { return }
		let waiterID = UUID()
		try await withTaskCancellationHandler(operation: {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				if Task.isCancelled {
					continuation.resume(throwing: CancellationError())
				} else if protectedDataAvailable() {
					continuation.resume()
				} else {
					protectedDataWaiters[waiterID] = continuation
				}
			}
		}, onCancel: {
			Task { @MainActor [weak self] in
				self?.cancelProtectedDataWaiter(waiterID)
			}
		})
	}

	private func cancelProtectedDataWaiter(_ waiterID: UUID) {
		protectedDataWaiters.removeValue(forKey: waiterID)?.resume(throwing: CancellationError())
	}

	var protectedDataWaiterCountForTesting: Int {
		protectedDataWaiters.count
	}

	private func observeProtectedDataAvailabilityIfNeeded() {
		if protectedDataObserver == nil {
			protectedDataObserver = NotificationCenter.default.addObserver(
				forName: UIApplication.protectedDataDidBecomeAvailableNotification,
				object: nil,
				queue: .main
			) { [weak self] _ in
				Task { @MainActor in
					self?.protectedDataDidBecomeAvailable()
				}
			}
		}

		// Unlock may have occurred between the failed check and observer registration.
		if protectedDataAvailable() {
			protectedDataDidBecomeAvailable()
		}
	}

	private func protectedDataDidBecomeAvailable() {
		if let protectedDataObserver {
			NotificationCenter.default.removeObserver(protectedDataObserver)
			self.protectedDataObserver = nil
		}
		let waiters = protectedDataWaiters.values
		protectedDataWaiters.removeAll()
		for waiter in waiters {
			waiter.resume()
		}
		guard state == .waitingForProtectedData else { return }
		state = .idle
		Task { @MainActor [weak self] in
			_ = try? await self?.ready()
		}
	}

	private static func makeContainer(
		inMemory: Bool,
		storeName: String
	) throws -> ModelContainer {
		let isTestEnvironment = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			storeName,
			schema: schema,
			isStoredInMemoryOnly: inMemory,
			allowsSave: true
		)

#if DEBUG
		if !inMemory && !isTestEnvironment && PerformanceSeedData.configuration?.resetStore == true {
			removeStoreFiles(at: config.url)
		}
#endif

		if !inMemory {
			sweepParkedStoreFiles(near: config.url)
			NodeBackupManager.sweepStagedBackupDirectories()
		}

		do {
			let container: ModelContainer
			if inMemory {
				container = try ModelContainer(for: schema, configurations: config)
			} else {
				container = try ModelContainer(
					for: schema,
					migrationPlan: MeshtasticMigrationPlan.self,
					configurations: config
				)
			}
			container.mainContext.autosaveEnabled = false
			Logger.data.info("💾 SwiftData store initialized successfully")
			return container
		} catch {
			guard !inMemory else { throw error }
			guard !storeExistsButIsUnreadable(at: config.url) else {
				Logger.data.info("💾 SwiftData store is unavailable until first unlock")
				throw ReadinessError.protectedDataUnavailable
			}

			Logger.data.critical("💾 SwiftData store failed to open, attempting recovery: \(error.localizedDescription, privacy: .public)")
			let fm = FileManager.default
			let storeURL = config.url
			let directory = storeURL.deletingLastPathComponent()
			let storeFileName = storeURL.lastPathComponent
			let suffix = "-broken-\(Int(Date().timeIntervalSince1970))"
			for sidecar in ["", "-shm", "-wal"] {
				let from = directory.appendingPathComponent(storeFileName + sidecar)
				let to = directory.appendingPathComponent(storeFileName + suffix + sidecar)
				try? fm.moveItem(at: from, to: to)
			}

			let recovered = try ModelContainer(
				for: schema,
				migrationPlan: MeshtasticMigrationPlan.self,
				configurations: config
			)
			recovered.mainContext.autosaveEnabled = false
			Logger.data.warning("💾 SwiftData store recreated after recovery — local data has been reset on this device")
			return recovered
		}
	}

	init(
		inMemory: Bool = false,
		storeName: String = "Meshtastic"
	) {
		self.storeName = storeName
		self.inMemory = inMemory
		state = .preparing
		readyContainer = nil
		startupLoader = nil
		protectedDataAvailable = { true }
		do {
			readyContainer = try Self.makeContainer(inMemory: inMemory, storeName: storeName)
			state = .ready
		} catch {
			fatalError("💾 SwiftData container initialization failed: \(error.localizedDescription)")
		}
	}

}

extension PersistenceController {

	@MainActor
	public func clearDatabase(includeRoutes: Bool = true) {
		// Delete + SAVE one model type at a time. A batch `delete(model:)` enqueues a deletion that is
		// committed on the next save and nullifies inverse relationships; reconciling MANY types'
		// deletions in a SINGLE trailing save tears down objects whose inverse targets were also
		// deleted in the same uncommitted batch and trips an internal SwiftData assertion (SIGTRAP).
		// Saving after each delete keeps every reconcile against already-committed, consistent state.
		// Mirrors MeshPackets.clearDatabase.
		do {
			// Sever tags AND images from the owning side before the batch deletes: batch-deleting
			// the images while a device still references them fails with "mandatory OTO nullify
			// inverse on DeviceHardwareImageEntity/device", aborting the whole clear.
			// Mirrors MeshPackets.clearDatabase.
			let hardwareDevices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
			for device in hardwareDevices {
				device.tags.removeAll()
				device.images.removeAll()
			}
			if container.mainContext.hasChanges {
				try container.mainContext.save()
			}

			// Delete entities that are on the inverse side of many-to-many
			// relationships first to avoid constraint trigger violations.
			try container.mainContext.delete(model: DeviceHardwareTagEntity.self)
			try container.mainContext.save()
			try container.mainContext.delete(model: DeviceHardwareImageEntity.self)
			try container.mainContext.save()
			// Clearing the image/link rows must also reset their refresh throttle so the next pass
			// restores them rather than skipping as "refreshed recently" (see MeshtasticAPI). Goes
			// through the throttle rather than writing the timestamp directly so an image/link pass
			// already in flight is superseded and cannot re-arm the throttle when it finishes.
			DeviceImageLinkThrottle.invalidate()

			for modelType in MeshtasticSchema.allModels {
				if !includeRoutes && (modelType == RouteEntity.self || modelType == LocationEntity.self) {
					continue
				}
				if modelType == DeviceHardwareTagEntity.self || modelType == DeviceHardwareImageEntity.self {
					continue // already deleted above
				}
				// This is the full app-data reset, so global rebuildable caches such as
				// EventFirmwareEntity are intentionally removed. Per-device clears preserve them.
				try container.mainContext.delete(model: modelType)
				try container.mainContext.save()
			}
			Logger.data.error("SwiftData database truncated. All app data has been erased.")
		} catch {
			Logger.data.error("Failed to clear SwiftData database: \(error.localizedDescription, privacy: .public)")
		}
	}
}
