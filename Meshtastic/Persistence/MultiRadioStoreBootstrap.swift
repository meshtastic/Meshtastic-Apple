// MultiRadioStoreBootstrap.swift
// Meshtastic

import Foundation
import SwiftData

struct MultiRadioStoreBootstrapResult: Equatable {
	let selectedProfileID: UUID?
	let selectedStoreKey: UUID?
}

@MainActor
enum MultiRadioStoreBootstrap {
	enum BootstrapError: Error {
		case selectedProfileMissing
		case selectedRadioStoreMissing
	}

	static func prepare(
		paths: RadioStorePaths,
		includeCoreDataMigration: Bool = true
	) throws -> MultiRadioStoreBootstrapResult {
		try FileManager.default.createDirectory(
			at: paths.radioStoreDirectory,
			withIntermediateDirectories: true
		)
		if includeCoreDataMigration {
			try migrateCoreDataIfNeeded(to: paths.legacyStoreURL)
		}

		let registryContainer = try RadioRegistryController.makeContainer(url: paths.registryStoreURL)
		if FileManager.default.fileExists(atPath: paths.legacyStoreURL.path) {
			_ = try LegacyRadioStoreMigrator.migrate(
				legacyStoreURL: paths.legacyStoreURL,
				radioStoreDirectory: paths.radioStoreDirectory,
				registryContainer: registryContainer
			)
		}

		let context = registryContainer.mainContext
		guard let metadata = try context.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).first,
		      let selectedProfileID = metadata.selectedProfileID else {
			return MultiRadioStoreBootstrapResult(selectedProfileID: nil, selectedStoreKey: nil)
		}
		guard let profile = try context.fetch(FetchDescriptor<RadioProfileEntity>())
			.first(where: { $0.id == selectedProfileID }) else {
			throw BootstrapError.selectedProfileMissing
		}
		guard FileManager.default.fileExists(atPath: paths.radioStoreURL(for: profile.storeKey).path) else {
			throw BootstrapError.selectedRadioStoreMissing
		}
		return MultiRadioStoreBootstrapResult(
			selectedProfileID: profile.id,
			selectedStoreKey: profile.storeKey
		)
	}
}

private extension MultiRadioStoreBootstrap {
	static func migrateCoreDataIfNeeded(to legacySwiftDataURL: URL) throws {
		CoreDataMigrationService.prepareForMigration()
		guard CoreDataMigrationService.legacyStoreExists() else { return }

		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(url: legacySwiftDataURL, allowsSave: true)
		let container = try ModelContainer(
			for: schema,
			migrationPlan: MeshtasticMigrationPlan.self,
			configurations: configuration
		)
		container.mainContext.autosaveEnabled = false
		try CoreDataMigrationService.migrate(into: container)
	}
}
