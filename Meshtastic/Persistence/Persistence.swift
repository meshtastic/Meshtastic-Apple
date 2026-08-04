//
//  Persistence.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/28/21.
//

import SwiftData
import OSLog
import Foundation

extension Foundation.Notification.Name {
	static let radioStoreDidChange = Foundation.Notification.Name("radioStoreDidChange")
}

@MainActor
class PersistenceController {

	static let shared: PersistenceController = {
		let isTestEnvironment = NSClassFromString("XCTestCase") != nil
			|| ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
		guard !isTestEnvironment else {
			return PersistenceController(inMemory: true)
		}

		do {
			let paths = try RadioStorePaths.production()
			let bootstrap = try MultiRadioStoreBootstrap.prepare(paths: paths)
			return try PersistenceController(
				multiRadioPaths: paths,
				selectedStoreKey: bootstrap.selectedStoreKey
			)
		} catch {
			Logger.data.critical("💾 Multi-radio bootstrap failed; using in-memory recovery stores: \(error.localizedDescription, privacy: .public)")
			return PersistenceController(combinedRecovery: ())
		}
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

	private(set) var container: ModelContainer
	private lazy var containerAccessCoordinator: ContainerAccessCoordinator = {
		let coordinator = ContainerAccessCoordinator(containerID: ObjectIdentifier(container))
		let access = ContainerWriteAccess(
			coordinator: coordinator,
			lease: coordinator.currentLease,
			containerID: ObjectIdentifier(container)
		)
		ContainerWriteAccessDirectory.shared.register(container, access: access)
		return coordinator
	}()

	var currentContainerLease: ContainerLease {
		containerAccessCoordinator.currentLease
	}

	var currentWriteAccess: ContainerWriteAccess {
		ContainerWriteAccess(
			coordinator: containerAccessCoordinator,
			lease: currentContainerLease,
			containerID: ObjectIdentifier(container)
		)
	}

	func requireCurrent(_ lease: ContainerLease) throws {
		try containerAccessCoordinator.requireCurrent(lease)
	}

	/// Remembered so the store can be reopened in a fresh container — see `recreateContainer()`.
	private let storeName: String
	private let inMemory: Bool
	private let usesCombinedLayout: Bool
	private let multiRadioPaths: RadioStorePaths?
	private(set) var activeRadioStoreKey: UUID?

	var activeRadioStoreURL: URL? {
		guard let multiRadioPaths, let activeRadioStoreKey else { return nil }
		return multiRadioPaths.radioStoreURL(for: activeRadioStoreKey)
	}

	var context: ModelContext {
		container.mainContext
	}

	/// Reopen the (already-migrated) store in a brand-new `ModelContainer`, replacing `container`.
	/// Active write permits drain before replacement, and new writes are rejected during the
	/// transition. Returns false when draining or opening fails and the old container remains live.
	@discardableResult
	func recreateContainer() async -> Bool {
		await replaceContainer(destroyStore: false)
	}

	/// Delete the on-disk store after active writers drain, then open a guaranteed-empty container.
	/// If the new disk store cannot open, an in-memory container becomes the active generation so
	/// no valid lease can continue targeting deleted files.
	@discardableResult
	func destroyStoreAndRecreateContainer() async -> Bool {
		await replaceContainer(destroyStore: !inMemory)
	}

	@discardableResult
	func selectRadioStore(_ storeKey: UUID?) async -> Bool {
		guard usesCombinedLayout else { return false }
		guard activeRadioStoreKey != storeKey else { return true }
		return await replaceCombinedContainer(destroyStore: false, targetStoreKey: storeKey)
	}

	private func replaceContainer(destroyStore: Bool) async -> Bool {
		if usesCombinedLayout {
			return await replaceCombinedContainer(
				destroyStore: destroyStore,
				targetStoreKey: activeRadioStoreKey
			)
		}
		let transition: ContainerTransition
		do {
			transition = try await containerAccessCoordinator.beginTransition(timeout: .seconds(5))
		} catch {
			Logger.data.error("💾 Container transition could not drain active writers: \(error.localizedDescription, privacy: .public)")
			return false
		}

		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			storeName,
			schema: schema,
			isStoredInMemoryOnly: inMemory,
			allowsSave: true
		)

		if destroyStore {
			Self.removeStoreFiles(at: config.url)
		}

		let fresh: ModelContainer
		do {
			if inMemory {
				fresh = try ModelContainer(for: schema, configurations: config)
			} else {
				fresh = try ModelContainer(
					for: schema,
					migrationPlan: MeshtasticMigrationPlan.self,
					configurations: config
				)
			}
		} catch {
			guard destroyStore else {
				try? containerAccessCoordinator.cancelTransition(transition)
				Logger.data.error("💾 Failed to recreate SwiftData container: \(error.localizedDescription, privacy: .public)")
				return false
			}

			let memoryConfig = ModelConfiguration(
				"\(storeName)-Recovery",
				schema: schema,
				isStoredInMemoryOnly: true,
				allowsSave: true
			)
			do {
				fresh = try ModelContainer(for: schema, configurations: memoryConfig)
				Logger.data.critical("💾 Destroyed store could not reopen; using an in-memory recovery container: \(error.localizedDescription, privacy: .public)")
			} catch let recoveryError {
				fatalError("💾 In-memory recovery container failed: \(recoveryError.localizedDescription)")
			}
		}

		fresh.mainContext.autosaveEnabled = false
		let retiredContainer = container
		container = fresh
		do {
			try containerAccessCoordinator.commitTransition(
				transition,
				newContainerID: ObjectIdentifier(fresh)
			)
		} catch {
			fatalError("💾 Container transition invariant failed: \(error.localizedDescription)")
		}
		ContainerWriteAccessDirectory.shared.register(fresh, access: currentWriteAccess)
		ContainerWriteAccessDirectory.shared.retire(retiredContainer)

		if destroyStore {
			Logger.data.warning("💾 Store files destroyed and container recreated (escalated database reset)")
		} else {
			Logger.data.info("💾 SwiftData container recreated after data clear")
		}
		return true
	}

	init(
		multiRadioPaths: RadioStorePaths,
		selectedStoreKey: UUID?
	) throws {
		storeName = "ActiveRadio"
		inMemory = false
		usesCombinedLayout = true
		self.multiRadioPaths = multiRadioPaths
		activeRadioStoreKey = selectedStoreKey
#if DEBUG
		if let selectedStoreKey, PerformanceSeedData.configuration?.resetStore == true {
			Self.removeStoreFiles(at: multiRadioPaths.radioStoreURL(for: selectedStoreKey))
		}
#endif
		container = try Self.makeCombinedContainer(
			paths: multiRadioPaths,
			storeKey: selectedStoreKey
		)
		_ = containerAccessCoordinator
	}

	private init(combinedRecovery: Void) {
		storeName = "RadioRecovery"
		inMemory = true
		usesCombinedLayout = true
		multiRadioPaths = nil
		activeRadioStoreKey = nil
		do {
			container = try Self.makeCombinedContainer(paths: nil, storeKey: nil)
		} catch {
			fatalError("💾 In-memory combined container failed: \(error.localizedDescription)")
		}
		_ = containerAccessCoordinator
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

	init(inMemory: Bool = false, storeName: String = "Meshtastic") {
		self.storeName = storeName
		self.inMemory = inMemory
		usesCombinedLayout = false
		multiRadioPaths = nil
		activeRadioStoreKey = nil
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
			Self.removeStoreFiles(at: config.url)
		}
#endif

		// ── Step 0: guard Core Data store from being clobbered ───────────────
		// Both the App Store (Core Data) build and this (SwiftData) build use
		// "Meshtastic.sqlite".  If we let SwiftData open the file first it will
		// corrupt the Core Data content.  Rename it out of the way so SwiftData
		// creates a fresh store; migration reads from the renamed file below.
		if !inMemory && !isTestEnvironment {
			CoreDataMigrationService.prepareForMigration()
		}

		// ── Step 1: build the SwiftData container ────────────────────────────
		do {
			if inMemory {
				container = try ModelContainer(
					for: schema,
					configurations: config
				)
			} else {
				container = try ModelContainer(
					for: schema,
					migrationPlan: MeshtasticMigrationPlan.self,
					configurations: config
				)
			}
			container.mainContext.autosaveEnabled = false
			Logger.data.info("💾 SwiftData store initialized successfully")
		} catch {
			// The store could not be opened (e.g. a Core Data file that
			// prepareForMigration() did not rename, or a corrupt store from a
			// previous build).  Log the error, rename the broken file so it is
			// preserved for diagnosis, and retry with a fresh empty store.
			// A fatalError here would leave users permanently unable to open
			// the app, so we recover instead and accept the data loss.
			Logger.data.critical("💾 SwiftData store failed to open, attempting recovery: \(error.localizedDescription, privacy: .public)")
			// Move the actual store files aside so the retry starts from a clean
			// slate. SwiftData names the store from `config.url` — for a named
			// configuration that is `<name>.store` with `-shm`/`-wal` siblings
			// (NOT `.sqlite`). Derive the paths from `config.url.lastPathComponent`
			// directly so we move the real files instead of a non-existent
			// `<name>.sqlite`, which previously left the broken store in place and
			// guaranteed the retry below failed.
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
			do {
				container = try ModelContainer(
					for: schema,
					migrationPlan: MeshtasticMigrationPlan.self,
					configurations: config
				)
				container.mainContext.autosaveEnabled = false
				Logger.data.warning("💾 SwiftData store recreated after recovery — local data has been reset on this device")
			} catch let recoveryError {
				// Last resort: never crash at launch. Fall back to an in-memory
				// container so the app remains usable (data not persisted this
				// session) instead of crash-looping on every launch.
				Logger.data.critical("💾 SwiftData store unrecoverable even after reset, falling back to in-memory: \(recoveryError.localizedDescription, privacy: .public)")
				let memoryConfig = ModelConfiguration(
					storeName,
					schema: schema,
					isStoredInMemoryOnly: true,
					allowsSave: true
				)
				do {
					container = try ModelContainer(for: schema, configurations: memoryConfig)
					container.mainContext.autosaveEnabled = false
				} catch let memoryError {
					// An in-memory store cannot fail for file reasons; if it does,
					// the schema itself is invalid and there is no safe recovery.
					fatalError("💾 SwiftData in-memory fallback failed: \(memoryError.localizedDescription)")
				}
			}
		}

		// Register the bootstrap container before any runtime writer can receive its context.
		_ = containerAccessCoordinator

		// ── Step 2: one-time Core Data → SwiftData migration ─────────────────
		// Runs only when upgrading from 2.7.12 (or earlier) which used Core Data.
		guard !inMemory, !isTestEnvironment else { return }
		if CoreDataMigrationService.legacyStoreExists() {
			do {
				try CoreDataMigrationService.migrate(into: container)
			} catch {
				// Log but do not crash — the SwiftData store is usable even if
				// migration fails; the user will simply start fresh on this device.
				Logger.data.error("⬆️ CoreDataMigrationService failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	@MainActor
	public func clearDatabase(includeRoutes: Bool = true) {
		let writePermit: ContainerWritePermit
		do {
			writePermit = try currentWriteAccess.beginWrite()
		} catch {
			Logger.data.error("Failed to clear SwiftData database: container is transitioning")
			return
		}
		defer { writePermit.finish() }

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
				try container.mainContext.coordinatedSave()
			}

			// Delete entities that are on the inverse side of many-to-many
			// relationships first to avoid constraint trigger violations.
			try container.mainContext.delete(model: DeviceHardwareTagEntity.self)
			try container.mainContext.coordinatedSave()
			try container.mainContext.delete(model: DeviceHardwareImageEntity.self)
			try container.mainContext.coordinatedSave()
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
				try container.mainContext.delete(model: modelType)
				try container.mainContext.coordinatedSave()
			}
			Logger.data.error("SwiftData database truncated. All app data has been erased.")
		} catch {
			Logger.data.error("Failed to clear SwiftData database: \(error.localizedDescription, privacy: .public)")
		}
	}
}

private extension PersistenceController {
	func replaceCombinedContainer(
		destroyStore: Bool,
		targetStoreKey: UUID?
	) async -> Bool {
		let transition: ContainerTransition
		do {
			transition = try await containerAccessCoordinator.beginTransition(timeout: .seconds(5))
		} catch {
			Logger.data.error("💾 Radio-store transition could not drain active writers: \(error.localizedDescription, privacy: .public)")
			return false
		}

		let replacementStoreKey = destroyStore ? nil : targetStoreKey
		let fresh: ModelContainer
		let activatedStoreKey: UUID?
		do {
			fresh = try Self.makeCombinedContainer(
				paths: multiRadioPaths,
				storeKey: replacementStoreKey
			)
			activatedStoreKey = replacementStoreKey
		} catch {
			guard destroyStore else {
				try? containerAccessCoordinator.cancelTransition(transition)
				Logger.data.error("💾 Failed to open selected radio store: \(error.localizedDescription, privacy: .public)")
				return false
			}
			do {
				fresh = try Self.makeCombinedContainer(paths: nil, storeKey: nil)
				activatedStoreKey = nil
				Logger.data.critical("💾 Destroyed radio store could not reopen; using in-memory recovery stores: \(error.localizedDescription, privacy: .public)")
			} catch let recoveryError {
				fatalError("💾 In-memory combined recovery container failed: \(recoveryError.localizedDescription)")
			}
		}

		let retiredContainer = container
		container = fresh
		activeRadioStoreKey = activatedStoreKey
		do {
			try containerAccessCoordinator.commitTransition(
				transition,
				newContainerID: ObjectIdentifier(fresh)
			)
		} catch {
			fatalError("💾 Radio-store transition invariant failed: \(error.localizedDescription)")
		}
		ContainerWriteAccessDirectory.shared.register(fresh, access: currentWriteAccess)
		ContainerWriteAccessDirectory.shared.retire(retiredContainer)
		if destroyStore {
			Logger.data.critical("💾 Retired the selected radio store without unlinking its live SQLite files; using an empty in-memory radio store")
		}
		return true
	}

	static func makeCombinedContainer(
		paths: RadioStorePaths?,
		storeKey: UUID?
	) throws -> ModelContainer {
		let radioConfiguration: ModelConfiguration
		if let paths, let storeKey {
			try FileManager.default.createDirectory(
				at: paths.radioStoreDirectory,
				withIntermediateDirectories: true
			)
			radioConfiguration = ModelConfiguration(
				"ActiveRadio",
				schema: MultiRadioStoreSchema.radioSchema,
				url: paths.radioStoreURL(for: storeKey),
				allowsSave: true
			)
		} else {
			radioConfiguration = ModelConfiguration(
				"UnassignedRadio",
				schema: MultiRadioStoreSchema.radioSchema,
				isStoredInMemoryOnly: true,
				allowsSave: true
			)
		}

		let globalConfiguration: ModelConfiguration
		if let paths {
			globalConfiguration = ModelConfiguration(
				"RadioRegistry",
				schema: MultiRadioStoreSchema.globalSchema,
				url: paths.registryStoreURL,
				allowsSave: true
			)
		} else {
			globalConfiguration = ModelConfiguration(
				"RadioRegistryRecovery",
				schema: MultiRadioStoreSchema.globalSchema,
				isStoredInMemoryOnly: true,
				allowsSave: true
			)
		}

		let container = try ModelContainer(
			for: MultiRadioStoreSchema.combinedSchema,
			configurations: radioConfiguration,
			globalConfiguration
		)
		container.mainContext.autosaveEnabled = false
		return container
	}
}
