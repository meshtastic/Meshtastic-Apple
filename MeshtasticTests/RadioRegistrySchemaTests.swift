// RadioRegistrySchemaTests.swift
// MeshtasticTests

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Radio registry schema")
@MainActor
struct RadioRegistrySchemaTests {
	@Test("version one owns phone routes and radio registry records")
	func schemaMembership() {
		let actual = Set(RadioRegistrySchemaV1.models.map { ObjectIdentifier($0) })
		let expected = Set([
			ObjectIdentifier(RouteEntity.self),
			ObjectIdentifier(LocationEntity.self),
			ObjectIdentifier(RadioProfileEntity.self),
			ObjectIdentifier(RadioTransportAliasEntity.self),
			ObjectIdentifier(RadioRegistryMetadataEntity.self)
		])

		#expect(actual == expected)
	}

	@Test("registry container opens independently")
	func opensIndependently() throws {
		let container = try RadioRegistryController.makeContainer(inMemory: true)
		let profile = RadioProfileEntity()
		container.mainContext.insert(profile)
		try container.mainContext.save()

		let profiles = try container.mainContext.fetch(FetchDescriptor<RadioProfileEntity>())
		let aliases = try container.mainContext.fetch(FetchDescriptor<RadioTransportAliasEntity>())
		#expect(profiles.map(\.id) == [profile.id])
		#expect(aliases.isEmpty)
		#expect(profile.storeKey != profile.id)
	}

	@Test("radio store destruction leaves registry file intact")
	func survivesRadioStoreDestruction() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let registryURL = directory.appendingPathComponent("registry.store")
		var registryContainer: ModelContainer? = try RadioRegistryController.makeContainer(url: registryURL)
		let profileID = UUID()
		registryContainer?.mainContext.insert(RadioProfileEntity(id: profileID))
		try registryContainer?.mainContext.save()
		registryContainer = nil

		let radioController = PersistenceController(inMemory: true, storeName: "radio-under-test")
		#expect(await radioController.destroyStoreAndRecreateContainer())

		let reopenedRegistry = try RadioRegistryController.makeContainer(url: registryURL)
		let profiles = try reopenedRegistry.mainContext.fetch(FetchDescriptor<RadioProfileEntity>())
		#expect(profiles.map(\.id) == [profileID])
	}
}
