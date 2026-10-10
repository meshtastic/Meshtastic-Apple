//
//  ConfigDownloadSaveTests.swift
//  MeshtasticTests
//
//  Feature 021, review V39: a connect's config download saves once, at its end, instead of once
//  per record; outside one, and for another radio (review V40-5), a config record saves at once.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("A connect's config download")
struct ConfigDownloadSaveTests {
	private let radioNum: Int64 = 0x0A0A_0A0A

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("ConfigDownload-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		let container = try ModelContainer(for: schema, configurations: config)
		let context = ModelContext(container)
		let node = NodeInfoEntity()
		node.num = radioNum
		context.insert(node)
		try context.save()
		return container
	}

	/// The role another context sees, so what's saved.
	private func savedRole(in container: ModelContainer) throws -> Int32? {
		let num = radioNum
		let nodes = try ModelContext(container).fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num }))
		return nodes.first?.deviceConfig?.role
	}

	@Test("Config records save at once outside a download, and together at the end of one")
	func savesOnceAtTheEnd() async throws {
		let container = try makeContainer()
		let packets = MeshPackets(modelContainer: container)
		var device = Config.DeviceConfig()
		device.role = .client

		// The answer to a Settings change, with no download running: saved at once.
		await packets.upsertDeviceConfigPacket(config: device, nodeNum: radioNum)
		#expect(try savedRole(in: container) == Int32(Config.DeviceConfig.Role.client.rawValue))

		// During a connect's download: held back until it ends.
		let radio = UUID()
		await packets.beginConfigDownload(radio, nodeNum: radioNum)
		device.role = .router
		await packets.upsertDeviceConfigPacket(config: device, nodeNum: radioNum)
		#expect(try savedRole(in: container) == Int32(Config.DeviceConfig.Role.client.rawValue), "not saved yet")

		await packets.endConfigDownload(radio)
		#expect(try savedRole(in: container) == Int32(Config.DeviceConfig.Role.router.rawValue), "saved with the download's end")
		#expect(await !packets.isDownloadingConfig(of: radioNum))
	}

	@Test("A new radio's MyInfo is saved at once during a download, so its id can be read back elsewhere")
	func myInfoSavedAtOnce() async throws {
		let container = try makeContainer()
		let packets = MeshPackets(modelContainer: container)
		await packets.beginConfigDownload(UUID(), nodeNum: nil)
		var info = MyNodeInfo()
		info.myNodeNum = 0x0B0B_0B0B
		let id = try #require(await packets.myInfoPacket(myInfo: info, peripheralId: UUID().uuidString))
		// What `handleMyInfo` does next; an unsaved insert's id traps here.
		let myInfo = try #require(try ModelContext(container).model(for: id) as? MyInfoEntity)
		#expect(myInfo.myNodeNum == 0x0B0B_0B0B)
	}

	@Test("During one radio's download, another radio's config record, a setting saved for it, saves at once")
	func otherRadioSavesAtOnce() async throws {
		let container = try makeContainer()
		let packets = MeshPackets(modelContainer: container)
		await packets.beginConfigDownload(UUID(), nodeNum: radioNum &+ 1)
		var device = Config.DeviceConfig()
		device.role = .router
		await packets.upsertDeviceConfigPacket(config: device, nodeNum: radioNum)
		#expect(try savedRole(in: container) == Int32(Config.DeviceConfig.Role.router.rawValue))
	}

	@Test("A radio the app doesn't know yet gets its number from its MyInfo, and its records then wait")
	func numberFromMyInfo() async throws {
		let container = try makeContainer()
		let packets = MeshPackets(modelContainer: container)
		let radio = UUID()
		await packets.beginConfigDownload(radio, nodeNum: nil)
		var info = MyNodeInfo()
		info.myNodeNum = UInt32(radioNum)
		_ = await packets.myInfoPacket(myInfo: info, peripheralId: radio.uuidString)
		var device = Config.DeviceConfig()
		device.role = .router
		await packets.upsertDeviceConfigPacket(config: device, nodeNum: radioNum)
		#expect(try savedRole(in: container) == nil, "not saved yet")
		await packets.endConfigDownload(radio)
		#expect(try savedRole(in: container) == Int32(Config.DeviceConfig.Role.router.rawValue))
	}
}
