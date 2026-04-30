//
//  MeshtasticMigrationPlan.swift
//  Meshtastic
//
//  SwiftData migration plan defining the ordered schema versions and
//  migration stages between them.
//
//  When adding a new schema version:
//  1. Create a new MeshtasticSchemaVN file with the updated models
//  2. Add it to the `schemas` array below (newest last)
//  3. Add a migration stage (lightweight or custom) to the `stages` array
//

import Foundation
import SwiftData

enum MeshtasticMigrationPlan: SchemaMigrationPlan {
	/// Ordered list of all schema versions from oldest to newest.
	/// SwiftData uses this ordering to determine which migrations to apply.
	static var schemas: [any VersionedSchema.Type] {
		[
			MeshtasticSchemaV1.self
		]
	}

	/// Migration stages between consecutive schema versions.
	/// Each stage maps one version to the next. Use `.lightweight` when
	/// SwiftData can infer the migration automatically (adding optional
	/// properties, renaming with @Attribute(originalName:), etc.).
	/// Use `.custom` when you need to transform data programmatically.
	static var stages: [MigrationStage] {
		[
			// No migrations yet — V1 is the initial version.
			// Future migrations go here, for example:
			// migrateV1toV2,
		]
	}

	// MARK: - Migration Stages
	// Uncomment and adapt when adding V2:
	//
	// static let migrateV1toV2 = MigrationStage.lightweight(
	//     fromVersion: MeshtasticSchemaV1.self,
	//     toVersion: MeshtasticSchemaV2.self
	// )
	//
	// For custom migrations that require data transformation:
	//
	// static let migrateV1toV2 = MigrationStage.custom(
	//     fromVersion: MeshtasticSchemaV1.self,
	//     toVersion: MeshtasticSchemaV2.self,
	//     willMigrate: { context in
	//         // Pre-migration: transform data in the old schema
	//     },
	//     didMigrate: { context in
	//         // Post-migration: populate new fields, clean up, etc.
	//         try context.save()
	//     }
	// )
}
