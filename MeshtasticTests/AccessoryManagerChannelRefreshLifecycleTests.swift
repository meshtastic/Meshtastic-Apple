//
//  AccessoryManagerChannelRefreshLifecycleTests.swift
//  MeshtasticTests
//

import Foundation
import SwiftData
import Testing

@testable import Meshtastic
import MeshtasticProtobufs

private actor ChannelRefreshLifecycleConnection: Connection {
	let type: TransportType = .ble
	var isConnected = true
	private(set) var sentWantConfigIDs: [UInt32] = []

	func send(_ data: ToRadio) async throws {
		if case let .wantConfigID(id) = data.payloadVariant {
			sentWantConfigIDs.append(id)
		}
	}
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws { isConnected = false }
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("Automatic channel refresh lifecycle", .serialized)
struct AccessoryManagerChannelRefreshLifecycleTests {
	private func resetSharedStore() {
		PersistenceController.shared.recreateContainer()
		MeshPackets.recreateShared()
	}

	private func makeManager(
		nodeNum: UInt32? = nil,
		connection: ChannelRefreshLifecycleConnection = ChannelRefreshLifecycleConnection()
	) -> AccessoryManager {
		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(),
			name: "Refresh Test Radio",
			transportType: .ble,
			identifier: "refresh-test-radio",
			connectionState: .connected,
			num: nodeNum.map(Int64.init)
		)
		manager.activeConnection = (device: device, connection: connection)
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		manager.updateState(.connecting)
		return manager
	}

	private func seedMyInfo(nodeNum: UInt32, channels: [(index: Int32, name: String, role: Channel.Role)]) throws {
		let context = PersistenceController.shared.context
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = Int64(nodeNum)

		context.insert(myInfo)
		for seeded in channels {
			let channel = ChannelEntity()
			channel.id = seeded.index
			channel.index = seeded.index
			channel.name = seeded.name
			channel.role = Int32(seeded.role.rawValue)
			context.insert(channel)
			myInfo.channels.append(channel)
		}
		try context.save()
		MeshPackets.recreateShared()
	}

	private func seedMyInfo(nodeNum: UInt32, channelName: String) throws {
		try seedMyInfo(nodeNum: nodeNum, channels: [(0, channelName, .primary)])
	}

	private func myInfo(nodeNum: UInt32) -> MyNodeInfo {
		var myInfo = MyNodeInfo()
		myInfo.myNodeNum = nodeNum
		return myInfo
	}

	private func channel(index: Int32, name: String, role: Channel.Role = .primary) -> Channel {
		var channel = Channel()
		channel.index = index
		channel.role = role
		channel.settings.name = name
		channel.settings.psk = Data([UInt8(truncatingIfNeeded: index), 0xAA])
		return channel
	}

	private func completeConfig(_ manager: AccessoryManager) async {
		await completeConfig(manager, id: UInt32(manager.NONCE_ONLY_CONFIG))
	}

	private func completeConfig(_ manager: AccessoryManager, id: UInt32) async {
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .configCompleteID(id)
		await manager.didReceive(.data(fromRadio))
	}

	private func channelNames(nodeNum: UInt32) throws -> [String] {
		let persistedNodeNum = Int64(nodeNum)
		let context = ModelContext(PersistenceController.shared.container)
		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == persistedNodeNum })
		return try context.fetch(descriptor).first?.channels
			.sorted { $0.index < $1.index }
			.map { $0.name ?? "" } ?? []
	}

	@Test("MyInfo refresh stages channels until config completion commits them")
	func myInfoRefreshStagesChannelsUntilConfigCompletionCommitsThem() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00C0_FFEE
		try seedMyInfo(nodeNum: nodeNum, channelName: "Old Primary")
		let manager = makeManager()

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "New Primary"))
		await manager.handleChannel(channel(index: 1, name: "New Secondary", role: .secondary))

		#expect(try channelNames(nodeNum: nodeNum) == ["Old Primary"])

		await completeConfig(manager)

		#expect(try channelNames(nodeNum: nodeNum) == ["New Primary", "New Secondary"])
	}

	@Test("Disconnect discards an unfinished automatic channel refresh")
	func disconnectDiscardsUnfinishedAutomaticChannelRefresh() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00D1_5C0
		try seedMyInfo(nodeNum: nodeNum, channelName: "Kept Primary")
		let manager = makeManager()

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Discarded Primary"))

		try await manager.closeConnection()
		await MeshPackets.shared.commitChannelRefreshStage(for: Int64(nodeNum))

		#expect(try channelNames(nodeNum: nodeNum) == ["Kept Primary"])
	}

	@Test("Late completion from an older automatic refresh cannot commit a newer stage")
	func lateOlderConfigCompletionCannotCommitNewerStage() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00A1_10CC
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)

		let firstRefresh = Task { try await manager.sendWantConfig() }
		while await connection.sentWantConfigIDs.count < 1 {
			await Task.yield()
		}
		let firstID = await connection.sentWantConfigIDs[0]
		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "First Primary"))

		let secondRefresh = Task { try await manager.sendWantConfig() }
		await #expect(throws: CancellationError.self) {
			try await firstRefresh.value
		}
		while await connection.sentWantConfigIDs.count < 2 {
			await Task.yield()
		}
		let secondID = await connection.sentWantConfigIDs[1]
		#expect(firstID != secondID)
		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Second Primary"))

		await completeConfig(manager, id: firstID)
		#expect(try channelNames(nodeNum: nodeNum) == ["Original Primary"])

		await completeConfig(manager, id: secondID)
		try await secondRefresh.value
		#expect(try channelNames(nodeNum: nodeNum) == ["Second Primary"])
	}

	@Test("A user deletion during automatic refresh is not resurrected by staged packets")
	func userDeletionDuringAutomaticRefreshIsNotResurrectedByStage() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00DE_1E7E
		try seedMyInfo(
			nodeNum: nodeNum,
			channels: [
				(0, "Primary", .primary),
				(1, "User Deleted", .secondary)
			]
		)
		let manager = makeManager(nodeNum: nodeNum)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Primary"))
		await manager.handleChannel(channel(index: 1, name: "User Deleted", role: .secondary))

		let context = PersistenceController.shared.context
		let persistedNodeNum = Int64(nodeNum)
		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == persistedNodeNum })
		let myInfo = try #require(context.fetch(descriptor).first)
		let deleted = try #require(myInfo.channels.first { $0.index == 1 })
		context.delete(deleted)
		try context.save()

		await completeConfig(manager)

		#expect(try channelNames(nodeNum: nodeNum) == ["Primary"])
	}

	@Test("Incomplete automatic refresh snapshot does not replace existing channels")
	func incompleteAutomaticRefreshSnapshotDoesNotReplaceExistingChannels() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x001C_0C00
		try seedMyInfo(
			nodeNum: nodeNum,
			channels: [
				(0, "Kept Primary", .primary),
				(1, "Kept Secondary", .secondary)
			]
		)
		let manager = makeManager(nodeNum: nodeNum)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 1, name: "Lone Secondary", role: .secondary))
		await completeConfig(manager)

		#expect(try channelNames(nodeNum: nodeNum) == ["Kept Primary", "Kept Secondary"])
	}

	@Test("Disabled channel in an automatic refresh removes the old slot")
	func disabledChannelInAutomaticRefreshRemovesOldSlot() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00D1_5A81
		try seedMyInfo(
			nodeNum: nodeNum,
			channels: [
				(0, "Old Primary", .primary),
				(1, "Old Secondary", .secondary)
			]
		)
		let manager = makeManager(nodeNum: nodeNum)
		var disabled = Channel()
		disabled.index = 1
		disabled.role = .disabled

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "New Primary"))
		await manager.handleChannel(disabled)
		await completeConfig(manager)

		#expect(try channelNames(nodeNum: nodeNum) == ["New Primary"])
	}
}
