// MultiRadioStoreSchemaTests.swift
// MeshtasticTests

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Multi-radio store schemas")
struct MultiRadioStoreSchemaTests {

	@Test("ownership covers production and registry schemas without overlap")
	func ownershipCoversAllSchemasWithoutOverlap() {
		let production = identifiers(for: MeshtasticSchema.allModels)
		let registry = identifiers(for: RadioRegistrySchemaV1.models)
		let radio = identifiers(for: MultiRadioStoreSchema.radioModels)
		let global = identifiers(for: MultiRadioStoreSchema.globalModels)

		#expect(radio.isDisjoint(with: global))
		#expect(radio.union(global) == production.union(registry))
		#expect(radio.count == 49)
		#expect(global == identifiers(for: [
			RouteEntity.self,
			LocationEntity.self,
			RadioProfileEntity.self,
			RadioTransportAliasEntity.self,
			RadioRegistryMetadataEntity.self
		]))
	}

	@Test("radio and global schemas create independent containers")
	@MainActor
	func radioAndGlobalSchemasCreateIndependentContainers() throws {
		let radioConfiguration = ModelConfiguration(
			"MultiRadioStoreSchemaTests-Radio",
			schema: MultiRadioStoreSchema.radioSchema,
			isStoredInMemoryOnly: true
		)
		let globalConfiguration = ModelConfiguration(
			"MultiRadioStoreSchemaTests-Global",
			schema: MultiRadioStoreSchema.globalSchema,
			isStoredInMemoryOnly: true
		)

		let radioContainer = try ModelContainer(
			for: MultiRadioStoreSchema.radioSchema,
			configurations: radioConfiguration
		)
		let globalContainer = try ModelContainer(
			for: MultiRadioStoreSchema.globalSchema,
			configurations: globalConfiguration
		)

		let node = NodeInfoEntity()
		node.num = 42
		radioContainer.mainContext.insert(node)

		let route = RouteEntity()
		route.name = "Phone route"
		let location = LocationEntity()
		location.routeLocation = route
		globalContainer.mainContext.insert(route)
		globalContainer.mainContext.insert(location)

		try radioContainer.mainContext.save()
		try globalContainer.mainContext.save()

		#expect(try radioContainer.mainContext.fetch(FetchDescriptor<NodeInfoEntity>()).count == 1)
		#expect(try globalContainer.mainContext.fetch(FetchDescriptor<RouteEntity>()).count == 1)
		#expect(try globalContainer.mainContext.fetch(FetchDescriptor<LocationEntity>()).count == 1)
	}

	@Test("combined container routes radio and global models to separate files")
	@MainActor
	func combinedContainerUsesSeparateFiles() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("MultiRadioCombined-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let radioURL = directory.appendingPathComponent("radio.store")
		let globalURL = directory.appendingPathComponent("global.store")
		var combined: ModelContainer? = try makeCombinedContainer(
			radioURL: radioURL,
			globalURL: globalURL
		)
		let node = NodeInfoEntity()
		node.num = 42
		let route = RouteEntity()
		route.name = "Global route"
		let profile = RadioProfileEntity()
		let profileID = profile.id
		combined?.mainContext.insert(node)
		combined?.mainContext.insert(route)
		combined?.mainContext.insert(profile)
		try combined?.mainContext.save()
		combined = nil

		let radioConfiguration = ModelConfiguration(
			url: radioURL,
			allowsSave: true
		)
		let radio = try ModelContainer(
			for: MultiRadioStoreSchema.radioSchema,
			configurations: radioConfiguration
		)
		let global = try RadioRegistryController.makeContainer(url: globalURL)

		#expect(try radio.mainContext.fetch(FetchDescriptor<NodeInfoEntity>()).map(\.num) == [42])
		#expect(try global.mainContext.fetch(FetchDescriptor<RouteEntity>()).map(\.name) == ["Global route"])
		#expect(try global.mainContext.fetch(FetchDescriptor<RadioProfileEntity>()).map(\.id) == [profileID])
	}

	@MainActor
	private func makeCombinedContainer(radioURL: URL, globalURL: URL) throws -> ModelContainer {
		let schema = MultiRadioStoreSchema.combinedSchema
		let radioConfiguration = ModelConfiguration(
			"Radio",
			schema: MultiRadioStoreSchema.radioSchema,
			url: radioURL,
			allowsSave: true
		)
		let globalConfiguration = ModelConfiguration(
			"Global",
			schema: MultiRadioStoreSchema.globalSchema,
			url: globalURL,
			allowsSave: true
		)
		let container = try ModelContainer(
			for: schema,
			configurations: radioConfiguration,
			globalConfiguration
		)
		container.mainContext.autosaveEnabled = false
		return container
	}

	private func identifiers(
		for models: [any PersistentModel.Type]
	) -> Set<ObjectIdentifier> {
		Set(models.map(ObjectIdentifier.init))
	}
}
