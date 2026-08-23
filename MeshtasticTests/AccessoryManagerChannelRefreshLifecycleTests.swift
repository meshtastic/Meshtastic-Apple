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

	func send(_ data: ToRadio) async throws {}
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

	private func makeManager() -> AccessoryManager {
		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(),
			name: "Refresh Test Radio",
			transportType: .ble,
			identifier: "refresh-test-radio",
			connectionState: .connected
		)
		manager.activeConnection = (device: device, connection: ChannelRefreshLifecycleConnection())
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		manager.updateState(.connecting)
		return manager
	}

	private func seedMyInfo(nodeNum: UInt32, channelName: String) throws {
		let context = PersistenceController.shared.context
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = Int64(nodeNum)

		let channel = ChannelEntity()
		channel.id = 0
		channel.index = 0
		channel.name = channelName
		channel.role = Int32(Channel.Role.primary.rawValue)

		context.insert(myInfo)
		context.insert(channel)
		myInfo.channels.append(channel)
		try context.save()
		MeshPackets.recreateShared()
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
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .configCompleteID(UInt32(manager.NONCE_ONLY_CONFIG))
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
}
