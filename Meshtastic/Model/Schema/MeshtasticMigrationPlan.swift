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
			// No migration stages have been defined. V1 shipped in v2.7.13 and
			// must not change again. Add a new schema and stage for later changes.
		]
	}
}
