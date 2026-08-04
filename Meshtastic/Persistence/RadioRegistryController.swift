// RadioRegistryController.swift
// Meshtastic

import Foundation
import SwiftData

@MainActor
final class RadioRegistryController {
	let container: ModelContainer

	init(inMemory: Bool = false, url: URL? = nil) throws {
		if inMemory {
			container = try Self.makeContainer(inMemory: true)
		} else {
			container = try Self.makeContainer(url: url ?? Self.defaultStoreURL())
		}
	}

	static func makeContainer(inMemory: Bool) throws -> ModelContainer {
		let schema = Schema(versionedSchema: RadioRegistrySchemaV1.self)
		let configuration = ModelConfiguration(
			"RadioRegistry",
			schema: schema,
			isStoredInMemoryOnly: inMemory,
			allowsSave: true
		)
		return try configuredContainer(schema: schema, configuration: configuration)
	}

	static func makeContainer(url: URL) throws -> ModelContainer {
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let schema = Schema(versionedSchema: RadioRegistrySchemaV1.self)
		let configuration = ModelConfiguration(url: url, allowsSave: true)
		return try configuredContainer(schema: schema, configuration: configuration)
	}

	private static func configuredContainer(
		schema: Schema,
		configuration: ModelConfiguration
	) throws -> ModelContainer {
		let container = try ModelContainer(
			for: schema,
			migrationPlan: RadioRegistryMigrationPlan.self,
			configurations: configuration
		)
		container.mainContext.autosaveEnabled = false
		return container
	}

	private static func defaultStoreURL() throws -> URL {
		let directory = try FileManager.default.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: true
		)
		return directory.appendingPathComponent("RadioRegistry.store")
	}
}
