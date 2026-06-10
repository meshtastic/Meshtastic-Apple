//
//  Persistence.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/28/21.
//

import SwiftData
import OSLog
import Foundation

@MainActor
class PersistenceController {

	static let shared: PersistenceController = {
		let isTestEnvironment = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
		return PersistenceController(inMemory: isTestEnvironment)
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

	/// Remembered so the store can be reopened in a fresh container — see `recreateContainer()`.
	private let storeName: String
	private let inMemory: Bool

	var context: ModelContext {
		container.mainContext
	}

	/// Reopen the (already-migrated) store in a brand-new `ModelContainer`, replacing `container`.
	///
	/// Used after a full data clear so every context — the main context and any actor contexts
	/// built from the container — starts with no stale object registrations. Without this, a
	/// long-lived context keeps the pre-clear objects registered; on reconnect SQLite reuses the
	/// freed rowids, so a fetch/relationship access returns a dead instance and SwiftData traps
	/// with "This model instance was destroyed by calling ModelContext.reset".
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
			container = fresh
			Logger.data.info("💾 SwiftData container recreated after data clear")
		} catch {
			Logger.data.error("💾 Failed to recreate SwiftData container: \(error.localizedDescription, privacy: .public)")
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

	init(inMemory: Bool = false, storeName: String = "Meshtastic") {
		self.storeName = storeName
		self.inMemory = inMemory
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
		do {
			let hardwareDevices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
			for device in hardwareDevices {
				device.tags.removeAll()
			}
			if container.mainContext.hasChanges {
				try container.mainContext.save()
			}

			// Delete entities that are on the inverse side of many-to-many
			// relationships first to avoid constraint trigger violations.
			try container.mainContext.delete(model: DeviceHardwareTagEntity.self)
			try container.mainContext.delete(model: DeviceHardwareImageEntity.self)

			for modelType in MeshtasticSchema.allModels {
				if !includeRoutes && (modelType == RouteEntity.self || modelType == LocationEntity.self) {
					continue
				}
				if modelType == DeviceHardwareTagEntity.self || modelType == DeviceHardwareImageEntity.self {
					continue // already deleted above
				}
				try container.mainContext.delete(model: modelType)
			}
			try container.mainContext.save()
			Logger.data.error("SwiftData database truncated. All app data has been erased.")
		} catch {
			Logger.data.error("Failed to clear SwiftData database: \(error.localizedDescription, privacy: .public)")
		}
	}
}
