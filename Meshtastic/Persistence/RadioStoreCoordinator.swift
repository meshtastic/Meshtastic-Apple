// RadioStoreCoordinator.swift
// Meshtastic

import Foundation
import SwiftData

enum RadioStorePreparation: Equatable {
	case selected(UUID)
	case unassigned
}

enum RadioStoreConfirmation: Equatable {
	case selected(profileID: UUID, changedStore: Bool)
	case quarantined([UUID])
	case ignored
}

@MainActor
final class RadioStoreCoordinator {
	typealias BeforeStoreChange = @MainActor () async -> Void

	enum CoordinationError: Error {
		case containerTransitionFailed
		case resolvedProfileMissing
		case backupProfileNotFound
		case backupProfileAmbiguous
		case backupIdentityMissing
		case backupIdentityMismatch
	}

	private let persistenceController: PersistenceController

	init(persistenceController: PersistenceController) {
		self.persistenceController = persistenceController
	}

	func prepareForConnection(
		to device: Device,
		beforeStoreChange: BeforeStoreChange? = nil
	) async throws -> RadioStorePreparation {
		let registry = try RadioIdentityRegistry(container: persistenceController.container)
		let key = RadioIdentityObservation(
			transport: device.transportType,
			transportDeviceID: device.id,
			identifier: device.identifier,
			deviceID: "unknown",
			nodeNum: nil
		).aliasKey

		guard let profile = try registry.aliases().first(where: { $0.key == key })?.profile,
		      profile.quarantineReason == nil else {
			try await selectBootstrapStore(beforeStoreChange: beforeStoreChange)
			return .unassigned
		}
		let profileID = profile.id
		let storeKey = profile.storeKey
		try await select(storeKey: storeKey, beforeStoreChange: beforeStoreChange)
		try persistSelection(profileID)
		return .selected(profileID)
	}

	func prepareForBackupRestore(
		nodeNum: Int64,
		expectedDeviceID: String?,
		beforeStoreChange: BeforeStoreChange? = nil
	) async throws -> UUID {
		let registry = try RadioIdentityRegistry(container: persistenceController.container)
		let profiles = try registry.profiles().filter {
			$0.nodeNum == nodeNum && $0.quarantineReason == nil
		}
		guard !profiles.isEmpty else { throw CoordinationError.backupProfileNotFound }
		guard profiles.count == 1, let profile = profiles.first else {
			throw CoordinationError.backupProfileAmbiguous
		}
		guard let expectedDeviceID,
		      let expectedDeviceID = RadioIdentityObservation.normalizedDeviceID(expectedDeviceID) else {
			throw CoordinationError.backupIdentityMissing
		}
		guard expectedDeviceID == profile.deviceID else {
			throw CoordinationError.backupIdentityMismatch
		}
		let profileID = profile.id
		let storeKey = profile.storeKey
		try await select(storeKey: storeKey, beforeStoreChange: beforeStoreChange)
		try persistSelection(profileID)
		return profileID
	}

	func confirmIdentity(
		_ observation: RadioIdentityObservation,
		beforeStoreChange: BeforeStoreChange? = nil
	) async throws -> RadioStoreConfirmation {
		let previousStoreKey = persistenceController.activeRadioStoreKey
		let registry = try RadioIdentityRegistry(container: persistenceController.container)
		let resolution = try registry.record(observation)

		switch resolution {
		case .resolved(let profileID):
			guard let profile = try registry.profiles().first(where: { $0.id == profileID }) else {
				throw CoordinationError.resolvedProfileMissing
			}
			guard profile.quarantineReason == nil else {
				try await selectBootstrapStore(beforeStoreChange: beforeStoreChange)
				return .quarantined([profileID])
			}
			let storeKey = profile.storeKey
			try await select(storeKey: storeKey, beforeStoreChange: beforeStoreChange)
			try persistSelection(profileID)
			return .selected(
				profileID: profileID,
				changedStore: previousStoreKey != storeKey
			)
		case .quarantined(let profileIDs):
			try await selectBootstrapStore(beforeStoreChange: beforeStoreChange)
			return .quarantined(profileIDs)
		case .ignored:
			try await selectBootstrapStore(beforeStoreChange: beforeStoreChange)
			return .ignored
		}
	}
}

private extension RadioStoreCoordinator {
	func select(
		storeKey: UUID?,
		beforeStoreChange: BeforeStoreChange?
	) async throws {
		if persistenceController.activeRadioStoreKey != storeKey {
			await beforeStoreChange?()
		}
		guard await persistenceController.selectRadioStore(storeKey) else {
			throw CoordinationError.containerTransitionFailed
		}
	}

	func selectBootstrapStore(beforeStoreChange: BeforeStoreChange?) async throws {
		try await select(storeKey: nil, beforeStoreChange: beforeStoreChange)
	}

	func persistSelection(_ profileID: UUID) throws {
		let context = persistenceController.context
		let metadata: RadioRegistryMetadataEntity
		if let existing = try context.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).first {
			metadata = existing
		} else {
			metadata = RadioRegistryMetadataEntity()
			context.insert(metadata)
		}
		metadata.selectedProfileID = profileID
		try context.coordinatedSave()
	}
}
