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
			MeshtasticSchemaV1.self,
			MeshtasticSchemaV2.self
		]
	}

	/// Migration stages between consecutive schema versions.
	/// Each stage maps one version to the next. Use `.lightweight` when
	/// SwiftData can infer the migration automatically (adding optional
	/// properties, renaming with @Attribute(originalName:), etc.).
	/// Use `.custom` when you need to transform data programmatically.
	/// V1 → V2: adds the additive WaypointEntity geofence fields (geofenceRadius,
	/// bounding-box corners, notifyOnEnter / notifyOnExit / notifyFavoritesOnly). All
	/// new fields carry defaults, so SwiftData can infer the migration automatically.
	static let migrateV1toV2 = MigrationStage.lightweight(
		fromVersion: MeshtasticSchemaV1.self,
		toVersion: MeshtasticSchemaV2.self
	)

	static var stages: [MigrationStage] {
		[
			migrateV1toV2
		]
	}
}
