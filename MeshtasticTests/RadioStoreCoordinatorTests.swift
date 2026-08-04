// RadioStoreCoordinatorTests.swift
// MeshtasticTests

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Radio store coordinator", .serialized)
@MainActor
struct RadioStoreCoordinatorTests {
	private let deviceA = "0011223344556677"
	private let deviceB = "8899aabbccddeeff"

	@Test("unknown transport alias selects empty bootstrap store")
	func unknownAliasSelectsBootstrap() async throws {
		let fixture = try makeFixture()
		let known = bleDevice("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
		let profileID = try await confirm(known, deviceID: deviceA, nodeNum: 1, coordinator: fixture.coordinator)
		let node = NodeInfoEntity()
		node.num = 101
		fixture.controller.context.insert(node)
		try fixture.controller.context.coordinatedSave()

		let unknown = bleDevice("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
		let preparation = try await fixture.coordinator.prepareForConnection(to: unknown)

		#expect(preparation == .unassigned)
		#expect(fixture.controller.activeRadioStoreKey == nil)
		#expect(try fixture.controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).isEmpty)
		#expect(try fixture.controller.context.fetch(FetchDescriptor<RadioProfileEntity>()).map(\.id) == [profileID])
	}

	@Test("canonical identity selects persistent store and known alias reopens it")
	func canonicalIdentitySelectsAndKnownAliasReopensStore() async throws {
		let fixture = try makeFixture()
		let device = bleDevice("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
		#expect(try await fixture.coordinator.prepareForConnection(to: device) == .unassigned)

		let confirmation = try await fixture.coordinator.confirmIdentity(
			observation(device, deviceID: deviceA, nodeNum: 1)
		)
		guard case .selected(let profileID, true) = confirmation else {
			Issue.record("canonical identity did not select a new profile")
			return
		}
		let selectedStoreKey = try #require(fixture.controller.activeRadioStoreKey)
		let node = NodeInfoEntity()
		node.num = 202
		fixture.controller.context.insert(node)
		try fixture.controller.context.coordinatedSave()

		#expect(await fixture.controller.selectRadioStore(nil))
		let preparation = try await fixture.coordinator.prepareForConnection(to: device)
		#expect(preparation == .selected(profileID))
		#expect(fixture.controller.activeRadioStoreKey == selectedStoreKey)
		#expect(try fixture.controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).map(\.num) == [202])
	}

	@Test("canonical identities isolate two radios")
	func canonicalIdentitiesIsolateRadios() async throws {
		let fixture = try makeFixture()
		let firstDevice = bleDevice("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
		let secondDevice = bleDevice("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
		_ = try await confirm(firstDevice, deviceID: deviceA, nodeNum: 1, coordinator: fixture.coordinator)
		let nodeA = NodeInfoEntity()
		nodeA.num = 301
		fixture.controller.context.insert(nodeA)
		try fixture.controller.context.coordinatedSave()

		_ = try await confirm(secondDevice, deviceID: deviceB, nodeNum: 2, coordinator: fixture.coordinator)
		#expect(try fixture.controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).isEmpty)
		let nodeB = NodeInfoEntity()
		nodeB.num = 302
		fixture.controller.context.insert(nodeB)
		try fixture.controller.context.coordinatedSave()

		#expect(try await fixture.coordinator.prepareForConnection(to: firstDevice).isSelected)
		#expect(try fixture.controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).map(\.num) == [301])
		#expect(try await fixture.coordinator.prepareForConnection(to: secondDevice).isSelected)
		#expect(try fixture.controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).map(\.num) == [302])
	}

	@Test("backup restore selects only the target profile store")
	func backupRestoreSelectsTargetStore() async throws {
		let fixture = try makeFixture()
		let firstDevice = bleDevice("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
		let secondDevice = bleDevice("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
		let firstProfileID = try await confirm(
			firstDevice,
			deviceID: deviceA,
			nodeNum: 100,
			coordinator: fixture.coordinator
		)
		_ = try await confirm(
			secondDevice,
			deviceID: deviceB,
			nodeNum: 200,
			coordinator: fixture.coordinator
		)
		let registryBeforeSelection = try RadioIdentityRegistry(container: fixture.controller.container)
		let firstStoreKey = try #require(
			try registryBeforeSelection.profiles().first { $0.id == firstProfileID }?.storeKey
		)

		let selected = try await fixture.coordinator.prepareForBackupRestore(
			nodeNum: 100,
			expectedDeviceID: deviceA
		)

		#expect(selected == firstProfileID)
		#expect(fixture.controller.activeRadioStoreKey == firstStoreKey)
		let metadata = try #require(
			try fixture.controller.context.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).first
		)
		#expect(metadata.selectedProfileID == firstProfileID)
	}

	@Test("backup restore fails closed for an unknown profile")
	func backupRestoreRejectsUnknownProfile() async throws {
		let fixture = try makeFixture()

		await #expect(throws: RadioStoreCoordinator.CoordinationError.backupProfileNotFound) {
			_ = try await fixture.coordinator.prepareForBackupRestore(
				nodeNum: 404,
				expectedDeviceID: deviceA
			)
		}
	}

	@Test("backup restore rejects missing or mismatched canonical identity")
	func backupRestoreRejectsWrongIdentity() async throws {
		let fixture = try makeFixture()
		let device = bleDevice("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
		_ = try await confirm(device, deviceID: deviceA, nodeNum: 100, coordinator: fixture.coordinator)

		await #expect(throws: RadioStoreCoordinator.CoordinationError.backupIdentityMissing) {
			_ = try await fixture.coordinator.prepareForBackupRestore(
				nodeNum: 100,
				expectedDeviceID: nil
			)
		}
		await #expect(throws: RadioStoreCoordinator.CoordinationError.backupIdentityMismatch) {
			_ = try await fixture.coordinator.prepareForBackupRestore(
				nodeNum: 100,
				expectedDeviceID: deviceB
			)
		}
	}

	@Test("reassigned TCP alias is quarantined before radio data is written")
	func reassignedTCPAliasReturnsToBootstrap() async throws {
		let fixture = try makeFixture()
		let endpoint = tcpDevice("mesh.local:4403")
		_ = try await confirm(endpoint, deviceID: deviceA, nodeNum: 1, coordinator: fixture.coordinator)
		#expect(fixture.controller.activeRadioStoreKey != nil)

		let result = try await fixture.coordinator.confirmIdentity(
			observation(endpoint, deviceID: deviceB, nodeNum: 2)
		)

		guard case .quarantined(let profileIDs) = result else {
			Issue.record("reassigned TCP endpoint was not quarantined")
			return
		}
		#expect(profileIDs.count == 2)
		#expect(fixture.controller.activeRadioStoreKey == nil)
		#expect(try fixture.controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).isEmpty)
	}

	private func confirm(
		_ device: Device,
		deviceID: String,
		nodeNum: Int64,
		coordinator: RadioStoreCoordinator
	) async throws -> UUID {
		let result = try await coordinator.confirmIdentity(
			observation(device, deviceID: deviceID, nodeNum: nodeNum)
		)
		guard case .selected(let profileID, _) = result else {
			throw ConfirmationError.notSelected
		}
		return profileID
	}

	private func observation(_ device: Device, deviceID: String, nodeNum: Int64) -> RadioIdentityObservation {
		RadioIdentityObservation(
			transport: device.transportType,
			transportDeviceID: device.id,
			identifier: device.identifier,
			deviceID: deviceID,
			nodeNum: nodeNum
		)
	}

	private func bleDevice(_ identifier: String) -> Device {
		Device(
			id: UUID(uuidString: identifier)!,
			name: "BLE",
			transportType: .ble,
			identifier: identifier
		)
	}

	private func tcpDevice(_ identifier: String) -> Device {
		Device(
			id: identifier.toUUIDFormatHash(),
			name: "TCP",
			transportType: .tcp,
			identifier: identifier
		)
	}

	private func makeFixture() throws -> Fixture {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("RadioStoreCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let controller = try PersistenceController(
			multiRadioPaths: RadioStorePaths(applicationSupportDirectory: directory),
			selectedStoreKey: nil
		)
		return Fixture(
			directory: directory,
			controller: controller,
			coordinator: RadioStoreCoordinator(persistenceController: controller)
		)
	}

	private enum ConfirmationError: Error {
		case notSelected
	}

	private final class Fixture {
		let directory: URL
		let controller: PersistenceController
		let coordinator: RadioStoreCoordinator

		init(directory: URL, controller: PersistenceController, coordinator: RadioStoreCoordinator) {
			self.directory = directory
			self.controller = controller
			self.coordinator = coordinator
		}
	}
}

private extension RadioStorePreparation {
	var isSelected: Bool {
		if case .selected = self { return true }
		return false
	}
}
