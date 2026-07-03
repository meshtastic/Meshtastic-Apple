//
//  MeshtasticSchema.swift
//  Meshtastic
//
//  SwiftData schema definition and migration plan for migrating from Core Data.
//

import Foundation
import SwiftData

/// All model types in the Meshtastic schema.
/// This provides a convenience accessor for the current schema version's models.
enum MeshtasticSchema {
	/// The current (latest) versioned schema.
	static var current: any VersionedSchema.Type {
		MeshtasticSchemaV1.self
	}

	/// All model types from the current schema version.
	static var allModels: [any PersistentModel.Type] {
		MeshtasticSchemaV1.models
	}
}
