//
//  Persistence.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/28/21.
//

import SwiftData
import OSLog

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

	var context: ModelContext {
		container.mainContext
	}

	init(inMemory: Bool = false, storeName: String = "Meshtastic") {
		let isTestEnvironment = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
		let schema = Schema(versionedSchema: MeshtasticSchema.current)

		let config = ModelConfiguration(
			storeName,
			schema: schema,
			isStoredInMemoryOnly: inMemory,
			allowsSave: true
		)

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
			let fm = FileManager.default
			let base = config.url.deletingPathExtension()
			let broken = base
				.deletingLastPathComponent()
				.appendingPathComponent(base.lastPathComponent + "-broken-\(Int(Date().timeIntervalSince1970))")
			for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {
				try? fm.moveItem(
					at: base.appendingPathExtension(ext),
					to: broken.appendingPathExtension(ext)
				)
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
				fatalError("💾 SwiftData store unrecoverable even after reset: \(recoveryError.localizedDescription)")
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
