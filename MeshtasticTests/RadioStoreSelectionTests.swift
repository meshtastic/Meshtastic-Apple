// RadioStoreSelectionTests.swift
// MeshtasticTests

import Foundation
import SwiftData
import Testing
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("Radio store selection", .serialized)
@MainActor
struct RadioStoreSelectionTests {
	@Test("switching isolates radio rows while global registry rows persist")
	func switchingIsolatesRadioRowsAndPreservesRegistry() async throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let paths = RadioStorePaths(applicationSupportDirectory: directory)
		let controller = try PersistenceController(multiRadioPaths: paths, selectedStoreKey: nil)
		let storeA = UUID()
		let storeB = UUID()
		let profileA = RadioProfileEntity(storeKey: storeA)
		let profileB = RadioProfileEntity(storeKey: storeB)
		controller.context.insert(profileA)
		controller.context.insert(profileB)
		try controller.context.coordinatedSave()

		#expect(await controller.selectRadioStore(storeA))
		let nodeA = NodeInfoEntity()
		nodeA.num = 101
		controller.context.insert(nodeA)
		try controller.context.coordinatedSave()

		#expect(await controller.selectRadioStore(storeB))
		#expect(try controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).isEmpty)
		#expect(try controller.context.fetch(FetchDescriptor<RadioProfileEntity>()).count == 2)
		let staleBContainer = controller.container
		let staleBContext = controller.context
		let nodeB = NodeInfoEntity()
		nodeB.num = 202
		staleBContext.insert(nodeB)
		try staleBContext.coordinatedSave()
		let lateBNode = NodeInfoEntity()
		lateBNode.num = 303
		staleBContext.insert(lateBNode)

		#expect(await controller.selectRadioStore(storeA))
		#expect(try controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).map(\.num) == [101])
		#expect(try controller.context.fetch(FetchDescriptor<RadioProfileEntity>()).count == 2)

		#expect(throws: ContainerLeaseError.self) {
			try staleBContext.coordinatedSave()
		}
		_ = staleBContainer
	}

	@Test("escalated reset retires radio store without unlinking live SQLite files")
	func escalatedResetRetiresRadioStoreWithoutUnlinking() async throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let paths = RadioStorePaths(applicationSupportDirectory: directory)
		let storeKey = UUID()
		let profileID = UUID()
		let controller = try PersistenceController(multiRadioPaths: paths, selectedStoreKey: storeKey)
		let retiredStoreURL = paths.radioStoreURL(for: storeKey)
		controller.context.insert(RadioProfileEntity(id: profileID, storeKey: storeKey))
		let node = NodeInfoEntity()
		node.num = 404
		controller.context.insert(node)
		try controller.context.coordinatedSave()

		#expect(await controller.destroyStoreAndRecreateContainer())
		#expect(controller.activeRadioStoreKey == nil)
		#expect(try controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).isEmpty)
		#expect(try controller.context.fetch(FetchDescriptor<RadioProfileEntity>()).map(\.id) == [profileID])
		#expect(FileManager.default.fileExists(atPath: retiredStoreURL.path))

		let retiredConfiguration = ModelConfiguration(url: retiredStoreURL, allowsSave: true)
		let retired = try ModelContainer(
			for: MultiRadioStoreSchema.radioSchema,
			configurations: retiredConfiguration
		)
		#expect(try retired.mainContext.fetch(FetchDescriptor<NodeInfoEntity>()).map(\.num) == [404])
	}

	@Test("existing MyInfo row refreshes canonical device ID")
	func existingMyInfoRefreshesDeviceID() async throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let controller = try PersistenceController(
			multiRadioPaths: RadioStorePaths(applicationSupportDirectory: directory),
			selectedStoreKey: UUID()
		)
		let packets = MeshPackets(
			modelContainer: controller.container,
			writeAccess: controller.currentWriteAccess
		)
		var first = MyNodeInfo()
		first.myNodeNum = 42
		first.deviceID = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77])
		_ = await packets.myInfoPacket(
			myInfo: first,
			peripheralId: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
		)

		var updated = first
		updated.deviceID = Data([0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])
		_ = await packets.myInfoPacket(
			myInfo: updated,
			peripheralId: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
		)

		let verificationContext = ModelContext(controller.container)
		let stored = try #require(try verificationContext.fetch(FetchDescriptor<MyInfoEntity>()).first)
		#expect(stored.deviceId == updated.deviceID)
	}

	private func makeTemporaryDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("RadioStoreSelectionTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}
}
