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

	static let shared = PersistenceController()

	static var preview: PersistenceController = {
		let result = PersistenceController(inMemory: true)
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

	init(inMemory: Bool = false) {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)

		let config = ModelConfiguration(
			"Meshtastic",
			schema: schema,
			isStoredInMemoryOnly: inMemory,
			allowsSave: true
		)

		do {
			container = try ModelContainer(
				for: schema,
				migrationPlan: MeshtasticMigrationPlan.self,
				configurations: config
			)
			container.mainContext.autosaveEnabled = true
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
			for modelType in MeshtasticSchema.allModels {
				if !includeRoutes && (modelType == RouteEntity.self || modelType == LocationEntity.self) {
					continue
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
