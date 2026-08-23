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
	private(set) var pendingPacketDrainStartCount = 0
	private var pauseNextConfigSend = false
	private var pausedConfigSendContinuation: CheckedContinuation<Void, Never>?
	private var failNextDrain = false

	func pauseNextWantConfigSend() {
		pauseNextConfigSend = true
	}

	func resumePausedWantConfigSend() {
		pausedConfigSendContinuation?.resume()
		pausedConfigSendContinuation = nil
	}

	func failNextPendingPacketDrain() {
		failNextDrain = true
	}

	func send(_ data: ToRadio) async throws {
		if case let .wantConfigID(id) = data.payloadVariant {
			sentWantConfigIDs.append(id)
			if pauseNextConfigSend {
				pauseNextConfigSend = false
				await withCheckedContinuation { continuation in
					pausedConfigSendContinuation = continuation
				}
			}
		}
	}
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws { isConnected = false }
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {
		pendingPacketDrainStartCount += 1
		if failNextDrain {
			failNextDrain = false
			throw AccessoryError.ioFailed("Simulated pending-packet drain failure")
		}
	}
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

	private func stageDisabledSlots(_ manager: AccessoryManager, excluding: Set<Int32> = []) async {
		for index in Int32(1)...Int32(7) where !excluding.contains(index) {
			var disabled = Channel()
			disabled.index = index
			disabled.role = .disabled
			await manager.handleChannel(disabled)
		}
	}

	private func stageDisabledSlotsOnMesh(_ mesh: MeshPackets, nodeNum: Int64) async {
		for index in Int32(1)...Int32(7) {
			var disabled = Channel()
			disabled.index = index
			disabled.role = .disabled
			await mesh.channelPacket(channel: disabled, fromNum: nodeNum)
		}
	}

	private func startAutomaticConfigRefresh(
		_ manager: AccessoryManager,
		connection: ChannelRefreshLifecycleConnection
	) async -> Task<Void, Error> {
		let refresh = Task { try await manager.sendWantConfig() }
		while await connection.sentWantConfigIDs.isEmpty {
			await Task.yield()
		}
		return refresh
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
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "New Primary"))
		await manager.handleChannel(channel(index: 1, name: "New Secondary", role: .secondary))
		await stageDisabledSlots(manager, excluding: [1])

		#expect(try channelNames(nodeNum: nodeNum) == ["Old Primary"])

		await completeConfig(manager)
		try await refresh.value

		#expect(try channelNames(nodeNum: nodeNum) == ["New Primary", "New Secondary"])
	}

	@Test("Disconnect discards an unfinished automatic channel refresh")
	func disconnectDiscardsUnfinishedAutomaticChannelRefresh() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00D1_5C0
		try seedMyInfo(nodeNum: nodeNum, channelName: "Kept Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Discarded Primary"))

		try await manager.closeConnection()
		await #expect(throws: CancellationError.self) {
			try await refresh.value
		}
		await MeshPackets.shared.commitChannelRefreshStage(for: Int64(nodeNum))

		#expect(try channelNames(nodeNum: nodeNum) == ["Kept Primary"])
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
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Primary"))
		await manager.handleChannel(channel(index: 1, name: "User Deleted", role: .secondary))
		await stageDisabledSlots(manager, excluding: [1])

		let context = PersistenceController.shared.context
		let persistedNodeNum = Int64(nodeNum)
		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == persistedNodeNum })
		let myInfo = try #require(context.fetch(descriptor).first)
		let deleted = try #require(myInfo.channels.first { $0.index == 1 })
		context.delete(deleted)
		try context.save()

		await completeConfig(manager)
		try await refresh.value

		#expect(try channelNames(nodeNum: nodeNum) == ["Primary"])
	}

	@Test("A user edit after wantConfig and before MyInfo discards the staged dump")
	func userEditBeforeMyInfoIsNotOverwrittenByAutomaticRefresh() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00B4_5E11
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		let context = PersistenceController.shared.context
		let persistedNodeNum = Int64(nodeNum)
		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == persistedNodeNum })
		let storedMyInfo = try #require(context.fetch(descriptor).first)
		storedMyInfo.channels[0].name = "User Edited Before MyInfo"
		try context.save()

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Remote Primary"))
		await stageDisabledSlots(manager)
		await completeConfig(manager)
		try await refresh.value

		#expect(try channelNames(nodeNum: nodeNum) == ["User Edited Before MyInfo"])
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
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 1, name: "Lone Secondary", role: .secondary))
		await completeConfig(manager)
		try await refresh.value

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
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)
		var disabled = Channel()
		disabled.index = 1
		disabled.role = .disabled

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "New Primary"))
		await manager.handleChannel(disabled)
		await stageDisabledSlots(manager)
		await completeConfig(manager)
		try await refresh.value

		#expect(try channelNames(nodeNum: nodeNum) == ["New Primary"])
	}

	@Test("Automatic refresh uses the reserved config nonce and coalesces before its waiter is installed")
	func automaticRefreshUsesReservedNonceAndCoalescesBeforeWaiterInstallation() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00AC_CE55
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		await connection.pauseNextWantConfigSend()

		let firstRefresh = Task { try await manager.sendWantConfig() }
		while await connection.sentWantConfigIDs.count < 1 {
			await Task.yield()
		}
		let secondRefresh = Task { try await manager.sendWantConfig() }
		for _ in 0..<100 {
			if await connection.sentWantConfigIDs.count >= 2 { break }
			await Task.yield()
		}

		let sentIDs = await connection.sentWantConfigIDs
		#expect(sentIDs == [UInt32(manager.NONCE_ONLY_CONFIG)])

		if sentIDs == [UInt32(manager.NONCE_ONLY_CONFIG)] {
			secondRefresh.cancel()
			await #expect(throws: CancellationError.self) {
				try await secondRefresh.value
			}
			await connection.resumePausedWantConfigSend()
			await completeConfig(manager)
			try await firstRefresh.value
		} else {
			firstRefresh.cancel()
			secondRefresh.cancel()
			await connection.resumePausedWantConfigSend()
		}
	}

	@Test("Duplicate MyInfo retains channels already staged for the active refresh")
	func duplicateMyInfoRetainsAccumulatedChannelsForActiveRefresh() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00D0_0D00
		try seedMyInfo(nodeNum: nodeNum, channelName: "Old Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "New Primary"))
		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 1, name: "New Secondary", role: .secondary))
		await stageDisabledSlots(manager, excluding: [1])
		await completeConfig(manager)
		try await refresh.value

		#expect(try channelNames(nodeNum: nodeNum) == ["New Primary", "New Secondary"])
	}

	@Test("A missing newly configured secondary slot rejects the complete-looking staged dump")
	func missingNewSecondarySlotDoesNotReplacePersistedChannels() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00B1_0C00
		try seedMyInfo(nodeNum: nodeNum, channelName: "Kept Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Replacement Primary"))
		await stageDisabledSlots(manager, excluding: [1])
		await completeConfig(manager)
		try await refresh.value

		#expect(try channelNames(nodeNum: nodeNum) == ["Kept Primary"])
	}

	@Test("An incomplete refresh stage is discarded so later channel packets update the cache")
	func incompleteRefreshStageIsDiscardedAfterCompletion() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00C1_EA00
		try seedMyInfo(nodeNum: nodeNum, channelName: "Kept Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 1, name: "Incomplete Secondary", role: .secondary))
		await completeConfig(manager)
		try await refresh.value
		await manager.handleChannel(channel(index: 0, name: "Later Packet"))

		#expect(try channelNames(nodeNum: nodeNum) == ["Later Packet"])
	}

	@Test("Recycling during an active refresh keeps later channel packets in that stage")
	func recycleDuringActiveRefreshDoesNotBypassStaging() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00EC_1E00
		try seedMyInfo(nodeNum: nodeNum, channelName: "Old Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "New Primary"))
		MeshPackets.recreateShared()
		MeshPackets.recreateShared()
		await manager.handleChannel(channel(index: 1, name: "New Secondary", role: .secondary))
		#expect(try channelNames(nodeNum: nodeNum) == ["Old Primary"])
		await stageDisabledSlots(manager, excluding: [1])
		await completeConfig(manager)
		try await refresh.value

		#expect(try channelNames(nodeNum: nodeNum) == ["New Primary", "New Secondary"])
	}

	@Test("Direct user rename deletion and reorder survive an automatic refresh")
	func directUserChannelChangesAreNotOverwrittenByAutomaticRefresh() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00D1_DEC7
		try seedMyInfo(
			nodeNum: nodeNum,
			channels: [
				(0, "Original Primary", .primary),
				(1, "Delete Me", .secondary),
				(2, "Move Me", .secondary)
			]
		)
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Remote Primary"))
		await manager.handleChannel(channel(index: 1, name: "Remote Secondary", role: .secondary))
		await manager.handleChannel(channel(index: 2, name: "Remote Moved", role: .secondary))
		await stageDisabledSlots(manager, excluding: [1, 2])

		try manager.applyLocalChannelMutation(
			channel(index: 0, name: "User Renamed Primary"),
			fromNum: Int64(nodeNum)
		)
		var deleted = Channel()
		deleted.index = 1
		deleted.role = .disabled
		try manager.applyLocalChannelMutation(deleted, fromNum: Int64(nodeNum))
		let context = PersistenceController.shared.context
		let persistedNodeNum = Int64(nodeNum)
		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == persistedNodeNum })
		let myInfo = try #require(context.fetch(descriptor).first)
		let moved = try #require(myInfo.channels.first { $0.index == 2 })
		moved.index = 1
		moved.id = 1
		try context.save()

		await completeConfig(manager)
		try await refresh.value

		#expect(try channelNames(nodeNum: nodeNum) == ["User Renamed Primary", "Move Me"])
	}

}

extension AccessoryManagerChannelRefreshLifecycleTests {
	@Test("Disconnect cancels a paused automatic refresh runner before it drains packets")
	func disconnectCancelsPausedAutomaticRefreshRunner() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00C1_05E0
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		await connection.pauseNextWantConfigSend()

		let refresh = Task { try await manager.sendWantConfig() }
		while await connection.sentWantConfigIDs.isEmpty {
			await Task.yield()
		}

		try await manager.closeConnection()
		await connection.resumePausedWantConfigSend()
		await #expect(throws: CancellationError.self) {
			try await refresh.value
		}
		for _ in 0..<100 {
			await Task.yield()
		}

		#expect(await connection.pendingPacketDrainStartCount == 0)
	}

	@Test("A main-context edit at the validated refresh boundary survives")
	func userEditAfterBaselineValidationCausesRefreshDiscard() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00B0_A4D1
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)
		let validationReached = AsyncGate()
		let allowCommitToContinue = AsyncGate()

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Remote Primary"))
		await stageDisabledSlots(manager)

		MeshPackets.channelRefreshCommitValidationHook = {
			await validationReached.open()
			try? await allowCommitToContinue.wait()
		}
		defer { MeshPackets.channelRefreshCommitValidationHook = nil }

		let completion = Task { await completeConfig(manager) }
		try await validationReached.wait()

		let context = PersistenceController.shared.context
		let persistedNodeNum = Int64(nodeNum)
		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == persistedNodeNum })
		let myInfo = try #require(context.fetch(descriptor).first)
		myInfo.channels[0].name = "User Primary"
		try context.save()

		await allowCommitToContinue.open()
		await completion.value
		try await refresh.value

		#expect(try channelNames(nodeNum: nodeNum) == ["User Primary"])
	}

	@Test("A successor staged refresh survives an older paused commit's cleanup")
	func successorStageSurvivesPausedOlderCommitCleanup() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00B0_A4D2
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original Primary")
		let sessionID = UUID()
		let staleOwner = AutomaticChannelRefreshOwner(sessionID: sessionID, generation: 1)
		let successorOwner = AutomaticChannelRefreshOwner(sessionID: sessionID, generation: 2)
		let staleLease = MeshPackets.acquireSharedChannelRefreshStageLease()
		#expect(await staleLease.begin(for: Int64(nodeNum), owner: staleOwner))

		await staleLease.packets.channelPacket(
			channel: channel(index: 0, name: "Stale Primary"),
			fromNum: Int64(nodeNum)
		)
		await stageDisabledSlotsOnMesh(staleLease.packets, nodeNum: Int64(nodeNum))

		let validationReached = AsyncGate()
		let allowCommitToContinue = AsyncGate()
		MeshPackets.channelRefreshCommitValidationHook = {
			await validationReached.open()
			try? await allowCommitToContinue.wait()
		}
		defer { MeshPackets.channelRefreshCommitValidationHook = nil }

		let staleCommit = Task {
			await staleLease.packets.commitChannelRefreshStage(for: Int64(nodeNum), owner: staleOwner)
		}
		try await validationReached.wait()

		let successorLease = MeshPackets.acquireSharedChannelRefreshStageLease()
		#expect(await successorLease.begin(for: Int64(nodeNum), owner: successorOwner))
		await allowCommitToContinue.open()
		await staleCommit.value

		// An incomplete successor must remain staged. If stale cleanup removed it, this packet
		// is handled directly and changes the persisted primary channel instead.
		await successorLease.packets.channelPacket(
			channel: channel(index: 0, name: "Successor Primary"),
			fromNum: Int64(nodeNum)
		)
		await successorLease.packets.commitChannelRefreshStage(for: Int64(nodeNum), owner: successorOwner)

		#expect(try channelNames(nodeNum: nodeNum) == ["Stale Primary"])
	}

	@Test("Cancelling the sole waiter keeps the in-flight fixed-nonce refresh alive for a later caller")
	func cancellingSoleWaiterDoesNotRetireInFlightRefresh() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00CA_11ED
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		await connection.pauseNextWantConfigSend()

		let cancelledWaiter = Task { try await manager.sendWantConfig() }
		while await connection.sentWantConfigIDs.count < 1 {
			await Task.yield()
		}
		cancelledWaiter.cancel()
		await #expect(throws: CancellationError.self) {
			try await cancelledWaiter.value
		}

		let joinedWaiter = Task { try await manager.sendWantConfig() }
		await Task.yield()
		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Refreshed Primary"))
		await stageDisabledSlots(manager)

		await connection.resumePausedWantConfigSend()
		await completeConfig(manager)
		try await joinedWaiter.value

		#expect(await connection.sentWantConfigIDs == [UInt32(manager.NONCE_ONLY_CONFIG)])
		#expect(try channelNames(nodeNum: nodeNum) == ["Refreshed Primary"])
	}

	@Test("A refresh lease prevents recycling after shared capture but before stage activation")
	func refreshLeaseMakesSharedCaptureAndRecycleGuardAtomic() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x001E_A5ED
		try seedMyInfo(nodeNum: nodeNum, channelName: "Old Primary")
		let owner = AutomaticChannelRefreshOwner(sessionID: UUID(), generation: 1)
		let lease = MeshPackets.acquireSharedChannelRefreshStageLease()
		let capturedMesh = lease.packets

		MeshPackets.recreateShared()
		#expect(MeshPackets.shared === capturedMesh)
		#expect(await lease.begin(for: Int64(nodeNum), owner: owner))

		await MeshPackets.shared.channelPacket(
			channel: channel(index: 0, name: "Leased Primary"),
			fromNum: Int64(nodeNum)
		)
		for index in Int32(1)...Int32(7) {
			var disabled = Channel()
			disabled.index = index
			disabled.role = .disabled
			await MeshPackets.shared.channelPacket(channel: disabled, fromNum: Int64(nodeNum))
		}
		#expect(try channelNames(nodeNum: nodeNum) == ["Old Primary"])

		await MeshPackets.shared.commitChannelRefreshStage(for: Int64(nodeNum), owner: owner)
		await Task.yield()

		#expect(try channelNames(nodeNum: nodeNum) == ["Leased Primary"])
	}

	@Test("A successor refresh stage survives stale owner cleanup")
	func successorRefreshStageSurvivesStaleOwnerCleanup() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x001E_A5EE
		try seedMyInfo(nodeNum: nodeNum, channelName: "Old Primary")
		let sessionID = UUID()
		let staleOwner = AutomaticChannelRefreshOwner(sessionID: sessionID, generation: 1)
		let successorOwner = AutomaticChannelRefreshOwner(sessionID: sessionID, generation: 2)
		let staleLease = MeshPackets.acquireSharedChannelRefreshStageLease()
		#expect(await staleLease.begin(for: Int64(nodeNum), owner: staleOwner))

		let successorLease = MeshPackets.acquireSharedChannelRefreshStageLease()
		#expect(await successorLease.begin(for: Int64(nodeNum), owner: successorOwner))
		await staleLease.packets.discardChannelRefreshStage(for: Int64(nodeNum), owner: staleOwner)

		await successorLease.packets.channelPacket(
			channel: channel(index: 0, name: "Successor Primary"),
			fromNum: Int64(nodeNum)
		)
		for index in Int32(1)...Int32(7) {
			var disabled = Channel()
			disabled.index = index
			disabled.role = .disabled
			await successorLease.packets.channelPacket(channel: disabled, fromNum: Int64(nodeNum))
		}
		await successorLease.packets.commitChannelRefreshStage(for: Int64(nodeNum), owner: successorOwner)

		#expect(try channelNames(nodeNum: nodeNum) == ["Successor Primary"])
	}

	@Test("Disconnect before delayed stage activation releases the late refresh lease")
	func disconnectBeforeDelayedStageActivationReleasesLateRefreshLease() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00D1_A17E
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)
		let stageBeginReached = AsyncGate()
		let allowStageBegin = AsyncGate()
		let capturedMesh = MeshPackets.shared

		MeshPackets.channelRefreshStageBeginHook = {
			await stageBeginReached.open()
			try? await allowStageBegin.wait()
		}
		defer { MeshPackets.channelRefreshStageBeginHook = nil }

		let delayedStageBegin = Task {
			await manager.beginAutomaticChannelRefreshStageIfNeeded(for: Int64(nodeNum))
		}
		try await stageBeginReached.wait()

		try await manager.closeConnection()
		await #expect(throws: CancellationError.self) {
			try await refresh.value
		}
		MeshPackets.recreateShared()
		#expect(MeshPackets.shared === capturedMesh)

		await allowStageBegin.open()
		await delayedStageBegin.value
		for _ in 0..<100 where MeshPackets.shared === capturedMesh {
			await Task.yield()
		}

		let didRecreateSharedMesh = MeshPackets.shared !== capturedMesh
		#expect(didRecreateSharedMesh)
	}

	@Test("A rejected refresh releases its stage so later radio packets use direct handling")
	func rejectedRefreshStageReturnsToDirectChannelHandling() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00AE_1EC7
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Remote Primary"))
		await stageDisabledSlots(manager)

		let context = PersistenceController.shared.context
		let persistedNodeNum = Int64(nodeNum)
		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == persistedNodeNum })
		let myInfo = try #require(context.fetch(descriptor).first)
		myInfo.channels[0].name = "User Primary"
		try context.save()

		await completeConfig(manager)
		try await refresh.value
		await manager.handleChannel(channel(index: 0, name: "Later Radio Primary"))

		#expect(try channelNames(nodeNum: nodeNum) == ["Later Radio Primary"])
	}

	@Test("A drain failure releases its lease and returns later packets to direct handling")
	func failedRefreshReturnsToDirectChannelHandling() async throws {
		resetSharedStore()
		let nodeNum: UInt32 = 0x00FA_11ED
		try seedMyInfo(nodeNum: nodeNum, channelName: "Original Primary")
		let connection = ChannelRefreshLifecycleConnection()
		let manager = makeManager(nodeNum: nodeNum, connection: connection)
		await connection.pauseNextWantConfigSend()
		await connection.failNextPendingPacketDrain()
		let refresh = await startAutomaticConfigRefresh(manager, connection: connection)

		await manager.handleMyInfo(myInfo(nodeNum: nodeNum))
		await manager.handleChannel(channel(index: 0, name: "Failed Refresh Primary"))
		let stagedMesh = MeshPackets.shared
		MeshPackets.recreateShared()
		#expect(MeshPackets.shared === stagedMesh)

		await connection.resumePausedWantConfigSend()
		await #expect(throws: AccessoryError.self) {
			try await refresh.value
		}
		await Task.yield()
		#expect(MeshPackets.shared !== stagedMesh)

		await manager.handleChannel(channel(index: 0, name: "Later Radio Primary"))
		#expect(try channelNames(nodeNum: nodeNum) == ["Later Radio Primary"])
	}
}
