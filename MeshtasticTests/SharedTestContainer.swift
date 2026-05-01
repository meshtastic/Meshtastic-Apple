// SharedTestContainer.swift
// MeshtasticTests
//
// Single shared ModelContainer for all SwiftData tests.
// Multiple containers with the same schema cause SwiftData context resets.

import SwiftData
@testable import Meshtastic

@MainActor
let sharedModelContainer: ModelContainer = {
	let schema = Schema(versionedSchema: MeshtasticSchema.current)
	let config = ModelConfiguration(
		"MeshtasticTestShared",
		schema: schema,
		isStoredInMemoryOnly: true,
		allowsSave: true
	)
	return try! ModelContainer(
		for: schema,
		migrationPlan: MeshtasticMigrationPlan.self,
		configurations: config
	)
}()
