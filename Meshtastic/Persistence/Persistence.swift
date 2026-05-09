//
//  Persistence.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/28/21.
//

import SwiftData
import CoreData
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

	let container: ModelContainer

	var context: ModelContext {
		container.mainContext
	}

	/// Core Data managed object context backed by the same SQLite store.
	/// Used by CoreDataBrowser for low-level database introspection.
	lazy var coreDataContext: NSManagedObjectContext? = {
		guard let storeURL = container.configurations.first?.url else {
			Logger.data.error("Could not determine SwiftData store URL for Core Data browser")
			return nil
		}
		guard let model = NSManagedObjectModel(contentsOf: storeURL) ?? inferredModel(at: storeURL) else {
			Logger.data.error("Could not load managed object model for Core Data browser")
			return nil
		}
		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		do {
			try coordinator.addPersistentStore(
				ofType: NSSQLiteStoreType,
				configurationName: nil,
				at: storeURL,
				options: [NSReadOnlyPersistentStoreOption: true]
			)
		} catch {
			Logger.data.error("Failed to open Core Data store for browser: \(error.localizedDescription, privacy: .public)")
			return nil
		}
		let ctx = NSManagedObjectContext(.mainQueue)
		ctx.persistentStoreCoordinator = coordinator
		return ctx
	}()

	private func inferredModel(at storeURL: URL) -> NSManagedObjectModel? {
		guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
			ofType: NSSQLiteStoreType,
			at: storeURL
		) else { return nil }
		return NSManagedObjectModel.mergedModel(from: nil, forStoreMetadata: metadata)
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
			Logger.data.error("SwiftData Error: \(error.localizedDescription, privacy: .public). Attempting to recreate database.")
			// Attempt recovery by creating in-memory store
			let fallbackConfig = ModelConfiguration(
				"Meshtastic",
				schema: schema,
				isStoredInMemoryOnly: true
			)
			do {
				container = try ModelContainer(for: schema, configurations: fallbackConfig)
				Logger.data.error("SwiftData database recreated in-memory. All app data has been lost.")
			} catch {
				fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
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
