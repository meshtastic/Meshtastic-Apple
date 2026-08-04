// LegacyRadioStoreMigrator.swift
// Meshtastic

import Foundation
import SwiftData

struct LegacyRadioStoreMigrationResult: Equatable {
	let profileID: UUID
	let storeKey: UUID
	let radioStoreURL: URL
	let legacyBackupURL: URL
}

@MainActor
enum LegacyRadioStoreMigrator {
	static let publicationSuffixes = ["-wal", "-shm", ""]

	static func migrate(
		legacyStoreURL: URL,
		radioStoreDirectory: URL,
		registryContainer: ModelContainer
	) throws -> LegacyRadioStoreMigrationResult {
		let legacyBackupURL = legacyStoreURL
			.deletingLastPathComponent()
			.appendingPathComponent("\(legacyStoreURL.lastPathComponent)-legacy-backup")
		if let completed = try completedResult(
			legacyStoreURL: legacyStoreURL,
			legacyBackupURL: legacyBackupURL,
			radioStoreDirectory: radioStoreDirectory,
			registryContainer: registryContainer
		) {
			return completed
		}
		let metadata = try migrationMetadata(in: registryContainer)
		let isResuming = metadata?.legacyMigrationStartedAt != nil
		if !isResuming, storeFilesExist(at: legacyBackupURL) {
			throw MigrationError.legacyBackupAlreadyExists
		}

		let fixture = try readLegacyStore(at: legacyStoreURL)
		let profile = try resolveProfile(for: fixture.identity, in: registryContainer)
		if let startedProfileID = metadata?.legacyMigrationProfileID,
		   startedProfileID != profile.id {
			throw MigrationError.startedMigrationProfileMismatch
		}
		let radioStoreURL = radioStoreDirectory
			.appendingPathComponent(profile.storeKey.uuidString.lowercased())
			.appendingPathExtension("store")

		try FileManager.default.createDirectory(
			at: radioStoreDirectory,
			withIntermediateDirectories: true
		)
		if !isResuming {
			guard !storeFilesExist(at: radioStoreURL) else {
				throw MigrationError.radioStoreAlreadyExists
			}
			try markMigrationStarted(for: profile.id, in: registryContainer)
		}
		try prepareRadioStore(
			from: legacyStoreURL,
			to: radioStoreURL,
			ownsExistingTarget: isResuming
		)
		try commitGlobalData(
			fixture.routes,
			selectedProfileID: profile.id,
			in: registryContainer
		)
		try ensureLegacyBackup(from: legacyStoreURL, to: legacyBackupURL)

		return LegacyRadioStoreMigrationResult(
			profileID: profile.id,
			storeKey: profile.storeKey,
			radioStoreURL: radioStoreURL,
			legacyBackupURL: legacyBackupURL
		)
	}
}

private extension LegacyRadioStoreMigrator {
	struct LegacyIdentity {
		let deviceID: String?
		let nodeNum: Int64?
		let peripheralID: UUID?
	}

	struct LegacyFixture {
		let identity: LegacyIdentity
		let routes: [RouteSnapshot]
	}

	struct RouteSnapshot {
		let color: Int64
		let date: Date?
		let distance: Double
		let elevationGain: Double
		let enabled: Bool
		let endDate: Date?
		let id: Int32
		let name: String?
		let notes: String?
		let locations: [LocationSnapshot]
	}

	struct LocationSnapshot {
		let altitude: Int32
		let heading: Int32
		let id: Int32
		let latitudeI: Int32
		let longitudeI: Int32
		let speed: Int32
	}

	enum MigrationError: Error {
		case legacyStoreMissing
		case legacyBackupAlreadyExists
		case legacyIdentityMissing
		case ambiguousLegacyIdentity
		case identityQuarantined
		case identityIgnored
		case radioStoreAlreadyExists
		case startedMigrationProfileMismatch
		case completedMigrationMissingRadioStore
		case completedMigrationMissingLegacyBackup
	}

	static func migrationMetadata(
		in container: ModelContainer
	) throws -> RadioRegistryMetadataEntity? {
		try container.mainContext.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).first
	}

	static func markMigrationStarted(
		for profileID: UUID,
		in container: ModelContainer
	) throws {
		let context = container.mainContext
		let metadata: RadioRegistryMetadataEntity
		if let existing = try migrationMetadata(in: container) {
			metadata = existing
		} else {
			metadata = RadioRegistryMetadataEntity()
			context.insert(metadata)
		}
		metadata.legacyMigrationProfileID = profileID
		metadata.legacyMigrationStartedAt = .now
		try context.save() // coordinated-save-allow: dedicated registry container is not radio-switched
	}

	static func completedResult(
		legacyStoreURL: URL,
		legacyBackupURL: URL,
		radioStoreDirectory: URL,
		registryContainer: ModelContainer
	) throws -> LegacyRadioStoreMigrationResult? {
		let context = registryContainer.mainContext
		guard let metadata = try context.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).first,
		      metadata.legacyMigrationCompletedAt != nil,
		      let migratedProfileID = metadata.legacyMigrationProfileID,
		      let profile = try context.fetch(FetchDescriptor<RadioProfileEntity>())
		            .first(where: { $0.id == migratedProfileID }) else {
			return nil
		}
		let radioStoreURL = radioStoreDirectory
			.appendingPathComponent(profile.storeKey.uuidString.lowercased())
			.appendingPathExtension("store")
		guard FileManager.default.fileExists(atPath: radioStoreURL.path) else {
			throw MigrationError.completedMigrationMissingRadioStore
		}
		try validateRadioStore(at: radioStoreURL)
		try ensureLegacyBackup(from: legacyStoreURL, to: legacyBackupURL)
		return LegacyRadioStoreMigrationResult(
			profileID: profile.id,
			storeKey: profile.storeKey,
			radioStoreURL: radioStoreURL,
			legacyBackupURL: legacyBackupURL
		)
	}

	static func readLegacyStore(at url: URL) throws -> LegacyFixture {
		guard FileManager.default.fileExists(atPath: url.path) else {
			throw MigrationError.legacyStoreMissing
		}

		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(url: url, allowsSave: true)
		let container = try ModelContainer(
			for: schema,
			migrationPlan: MeshtasticMigrationPlan.self,
			configurations: configuration
		)
		container.mainContext.autosaveEnabled = false

		let myInfos = try container.mainContext.fetch(FetchDescriptor<MyInfoEntity>())
		let identities = myInfos.compactMap(legacyIdentity)
		guard let identity = identities.first else {
			throw MigrationError.legacyIdentityMissing
		}
		guard identities.dropFirst().allSatisfy({ identitiesMatch(identity, $0) }) else {
			throw MigrationError.ambiguousLegacyIdentity
		}

		let routes = try container.mainContext.fetch(FetchDescriptor<RouteEntity>()).map { route in
			RouteSnapshot(
				color: route.color,
				date: route.date,
				distance: route.distance,
				elevationGain: route.elevationGain,
				enabled: route.enabled,
				endDate: route.endDate,
				id: route.id,
				name: route.name,
				notes: route.notes,
				locations: route.locations.map { location in
					LocationSnapshot(
						altitude: location.altitude,
						heading: location.heading,
						id: location.id,
						latitudeI: location.latitudeI,
						longitudeI: location.longitudeI,
						speed: location.speed
					)
				}
			)
		}
		return LegacyFixture(identity: identity, routes: routes)
	}

	static func legacyIdentity(_ myInfo: MyInfoEntity) -> LegacyIdentity? {
		let deviceID = normalizedDeviceID(myInfo.deviceId)
		let nodeNum = myInfo.myNodeNum > 0 ? myInfo.myNodeNum : nil
		let peripheralID = myInfo.peripheralId.flatMap(UUID.init(uuidString:))
		guard deviceID != nil || nodeNum != nil else { return nil }
		return LegacyIdentity(
			deviceID: deviceID,
			nodeNum: nodeNum,
			peripheralID: peripheralID
		)
	}

	static func normalizedDeviceID(_ data: Data?) -> String? {
		guard let data else { return nil }
		return RadioIdentityObservation.normalizedDeviceID(data)
	}

	static func identitiesMatch(_ lhs: LegacyIdentity, _ rhs: LegacyIdentity) -> Bool {
		if let leftDeviceID = lhs.deviceID, let rightDeviceID = rhs.deviceID {
			return leftDeviceID == rightDeviceID
		}
		return lhs.nodeNum == rhs.nodeNum && lhs.peripheralID == rhs.peripheralID
	}

	static func resolveProfile(
		for identity: LegacyIdentity,
		in container: ModelContainer
	) throws -> RadioProfileEntity {
		let registry = try RadioIdentityRegistry(container: container)
		if let peripheralID = identity.peripheralID {
			let resolution = try registry.record(
				RadioIdentityObservation(
					transport: .ble,
					transportDeviceID: peripheralID,
					identifier: peripheralID.uuidString,
					deviceID: identity.deviceID ?? "unknown",
					nodeNum: identity.nodeNum
				)
			)
			switch resolution {
			case .resolved(let profileID):
				guard let profile = try registry.profiles().first(where: { $0.id == profileID }) else {
					throw MigrationError.identityIgnored
				}
				guard profile.quarantineReason == nil else {
					throw MigrationError.identityQuarantined
				}
				return profile
			case .quarantined:
				throw MigrationError.identityQuarantined
			case .ignored:
				throw MigrationError.identityIgnored
			}
		}

		let existingProfiles = try registry.profiles()
		let matchingProfiles: [RadioProfileEntity]
		if let deviceID = identity.deviceID {
			matchingProfiles = existingProfiles.filter { $0.deviceID == deviceID }
		} else {
			matchingProfiles = existingProfiles.filter {
				$0.deviceID == nil && $0.nodeNum == identity.nodeNum
			}
		}
		guard matchingProfiles.count <= 1 else {
			throw MigrationError.identityQuarantined
		}
		if let profile = matchingProfiles.first {
			guard profile.quarantineReason == nil else {
				throw MigrationError.identityQuarantined
			}
			return profile
		}

		let profile = RadioProfileEntity(
			deviceID: identity.deviceID,
			nodeNum: identity.nodeNum
		)
		container.mainContext.insert(profile)
		try container.mainContext.save() // coordinated-save-allow: dedicated registry container is not radio-switched
		return profile
	}

	static func prepareRadioStore(
		from source: URL,
		to destination: URL,
		ownsExistingTarget: Bool
	) throws {
		if storeFilesExist(at: destination) {
			guard ownsExistingTarget else {
				throw MigrationError.radioStoreAlreadyExists
			}
			if FileManager.default.fileExists(atPath: destination.path) {
				do {
					try validateRadioStore(at: destination)
					return
				} catch {
					removeStoreFiles(at: destination)
				}
			} else {
				// A prior sidecar-first move stopped before publishing the main file. The
				// legacy source is still intact, so discard the incomplete destination.
				removeStoreFiles(at: destination)
			}
		}

		let staging = destination
			.deletingLastPathComponent()
			.appendingPathComponent(".\(destination.lastPathComponent).migrating")
		removeStoreFiles(at: staging)
		defer { removeStoreFiles(at: staging) }

		try copyStoreFiles(from: source, to: staging)
		try validateRadioStore(at: staging)
		try moveStoreFiles(from: staging, to: destination)
	}

	static func validateRadioStore(at url: URL) throws {
		let configuration = ModelConfiguration(url: url, allowsSave: true)
		let container = try ModelContainer(
			for: MultiRadioStoreSchema.radioSchema,
			configurations: configuration
		)
		container.mainContext.autosaveEnabled = false
		_ = try container.mainContext.fetch(FetchDescriptor<MyInfoEntity>())
	}

	static func commitGlobalData(
		_ snapshots: [RouteSnapshot],
		selectedProfileID: UUID,
		in container: ModelContainer
	) throws {
		let context = container.mainContext
		do {
			for snapshot in snapshots {
				let route = RouteEntity()
				route.color = snapshot.color
				route.date = snapshot.date
				route.distance = snapshot.distance
				route.elevationGain = snapshot.elevationGain
				route.enabled = snapshot.enabled
				route.endDate = snapshot.endDate
				route.id = snapshot.id
				route.name = snapshot.name
				route.notes = snapshot.notes
				context.insert(route)

				for locationSnapshot in snapshot.locations {
					let location = LocationEntity()
					location.altitude = locationSnapshot.altitude
					location.heading = locationSnapshot.heading
					location.id = locationSnapshot.id
					location.latitudeI = locationSnapshot.latitudeI
					location.longitudeI = locationSnapshot.longitudeI
					location.speed = locationSnapshot.speed
					context.insert(location)
					route.locations.append(location)
				}
			}

			let metadata: RadioRegistryMetadataEntity
			if let existing = try context.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).first {
				metadata = existing
			} else {
				metadata = RadioRegistryMetadataEntity()
				context.insert(metadata)
			}
			guard metadata.legacyMigrationProfileID == selectedProfileID else {
				throw MigrationError.startedMigrationProfileMismatch
			}
			metadata.selectedProfileID = selectedProfileID
			metadata.legacyMigrationCompletedAt = .now
			try context.save() // coordinated-save-allow: dedicated registry container is not radio-switched
		} catch {
			context.rollback()
			throw error
		}
	}

	static func ensureLegacyBackup(from source: URL, to backup: URL) throws {
		let sourceHasMainStore = FileManager.default.fileExists(atPath: source.path)
		let backupHasMainStore = FileManager.default.fileExists(atPath: backup.path)

		if sourceHasMainStore {
			removeStoreFiles(at: backup)
			try archiveStore(from: source, to: backup)
			return
		}
		guard backupHasMainStore else {
			throw MigrationError.completedMigrationMissingLegacyBackup
		}
		try validateLegacyStore(at: backup)
		removeStoreFiles(at: source)
	}

	static func archiveStore(from source: URL, to backup: URL) throws {
		let staging = backup
			.deletingLastPathComponent()
			.appendingPathComponent(".\(backup.lastPathComponent).archiving")
		removeStoreFiles(at: staging)
		defer { removeStoreFiles(at: staging) }

		try copyStoreFiles(from: source, to: staging)
		try validateLegacyStore(at: staging)
		try moveStoreFiles(from: staging, to: backup)
		try validateLegacyStore(at: backup)
		removeStoreFiles(at: source)
	}

	static func validateLegacyStore(at url: URL) throws {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(url: url, allowsSave: true)
		let container = try ModelContainer(
			for: schema,
			migrationPlan: MeshtasticMigrationPlan.self,
			configurations: configuration
		)
		container.mainContext.autosaveEnabled = false
		_ = try container.mainContext.fetch(FetchDescriptor<MyInfoEntity>())
	}

	static func copyStoreFiles(from source: URL, to destination: URL) throws {
		for suffix in publicationSuffixes {
			let sourceFile = URL(fileURLWithPath: source.path + suffix)
			guard FileManager.default.fileExists(atPath: sourceFile.path) else { continue }
			let destinationFile = URL(fileURLWithPath: destination.path + suffix)
			try FileManager.default.copyItem(at: sourceFile, to: destinationFile)
		}
	}

	static func moveStoreFiles(from source: URL, to destination: URL) throws {
		for suffix in publicationSuffixes {
			let sourceFile = URL(fileURLWithPath: source.path + suffix)
			guard FileManager.default.fileExists(atPath: sourceFile.path) else { continue }
			let destinationFile = URL(fileURLWithPath: destination.path + suffix)
			try FileManager.default.moveItem(at: sourceFile, to: destinationFile)
		}
	}

	static func storeFilesExist(at url: URL) -> Bool {
		["", "-shm", "-wal"].contains { suffix in
			FileManager.default.fileExists(atPath: url.path + suffix)
		}
	}

	static func removeStoreFiles(at url: URL) {
		for suffix in ["", "-shm", "-wal"] {
			try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
		}
	}
}
