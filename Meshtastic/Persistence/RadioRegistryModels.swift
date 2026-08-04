// RadioRegistryModels.swift
// Meshtastic

import Foundation
import SwiftData

@Model
final class RadioProfileEntity {
	@Attribute(.unique) var id: UUID
	@Attribute(.unique) var storeKey: UUID
	var deviceID: String?
	var nodeNum: Int64?
	var createdAt: Date
	var lastSeenAt: Date
	var quarantineReason: String?

	@Relationship(deleteRule: .cascade, inverse: \RadioTransportAliasEntity.profile)
	var aliases: [RadioTransportAliasEntity] = []

	init(
		id: UUID = UUID(),
		storeKey: UUID = UUID(),
		deviceID: String? = nil,
		nodeNum: Int64? = nil,
		createdAt: Date = .now,
		lastSeenAt: Date = .now,
		quarantineReason: String? = nil
	) {
		self.id = id
		self.storeKey = storeKey
		self.deviceID = deviceID
		self.nodeNum = nodeNum
		self.createdAt = createdAt
		self.lastSeenAt = lastSeenAt
		self.quarantineReason = quarantineReason
	}
}

@Model
final class RadioTransportAliasEntity {
	@Attribute(.unique) var key: String
	var transport: String
	var identifier: String
	var transportDeviceID: UUID
	var firstSeenAt: Date
	var lastSeenAt: Date
	var profile: RadioProfileEntity?

	init(
		key: String,
		transport: String,
		identifier: String,
		transportDeviceID: UUID,
		firstSeenAt: Date = .now,
		lastSeenAt: Date = .now
	) {
		self.key = key
		self.transport = transport
		self.identifier = identifier
		self.transportDeviceID = transportDeviceID
		self.firstSeenAt = firstSeenAt
		self.lastSeenAt = lastSeenAt
	}
}

@Model
final class RadioRegistryMetadataEntity {
	@Attribute(.unique) var id: String
	var selectedProfileID: UUID?
	var legacyMigrationProfileID: UUID?
	var legacyMigrationStartedAt: Date?
	var legacyMigrationCompletedAt: Date?

	init(
		id: String = "registry",
		selectedProfileID: UUID? = nil,
		legacyMigrationProfileID: UUID? = nil,
		legacyMigrationStartedAt: Date? = nil,
		legacyMigrationCompletedAt: Date? = nil
	) {
		self.id = id
		self.selectedProfileID = selectedProfileID
		self.legacyMigrationProfileID = legacyMigrationProfileID
		self.legacyMigrationStartedAt = legacyMigrationStartedAt
		self.legacyMigrationCompletedAt = legacyMigrationCompletedAt
	}
}

enum RadioRegistrySchemaV1: VersionedSchema {
	static let versionIdentifier = Schema.Version(1, 0, 0)
	static let models: [any PersistentModel.Type] = [
		RouteEntity.self,
		LocationEntity.self,
		RadioProfileEntity.self,
		RadioTransportAliasEntity.self,
		RadioRegistryMetadataEntity.self
	]
}

enum RadioRegistryMigrationPlan: SchemaMigrationPlan {
	static let schemas: [any VersionedSchema.Type] = [
		RadioRegistrySchemaV1.self
	]
	static let stages: [MigrationStage] = []
}
