//
//  MultiRadioIngestTests.swift
//  MeshtasticTests
//
//  Feature 021 ingest: which local radio heard a packet, per-radio node observations and
//  their aggregate, and messages stored once per sender and packet id.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Per-radio ingest")
@MainActor
struct MultiRadioIngestTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B
	private let remote: Int64 = 0x1234_5678

	// MARK: - Helpers

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"MultiRadioIngestTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return try ModelContainer(for: schema, configurations: config)
	}

	private func makePackets(_ container: ModelContainer) async -> MeshPackets {
		let packets = MeshPackets(modelContainer: container)
		await packets.replaceNotificationScheduler { @MainActor @Sendable _ in }
		return packets
	}

	private func seedNodes(_ nums: [Int64], in container: ModelContainer) throws {
		let context = ModelContext(container)
		for num in nums {
			let node = NodeInfoEntity()
			node.num = num
			node.id = num
			context.insert(node)
			let user = UserEntity()
			user.num = num
			user.userNode = node
			context.insert(user)
		}
		try context.save()
	}

	private func packet(id: UInt32, from: Int64, to: UInt32 = Constants.maximumNodeNum, text: String? = nil, snr: Float = 0, hopStart: UInt32 = 0, hopLimit: UInt32 = 0) -> MeshPacket {
		var data = DataMessage()
		data.portnum = text == nil ? .positionApp : .textMessageApp
		data.payload = Data((text ?? "").utf8)
		var packet = MeshPacket()
		packet.id = id
		packet.from = UInt32(from)
		packet.to = to
		packet.rxTime = 1_800_000_000
		packet.rxSnr = snr
		packet.hopStart = hopStart
		packet.hopLimit = hopLimit
		packet.decoded = data
		return packet
	}

	private func fetch<T: PersistentModel>(_ type: T.Type, in container: ModelContainer) throws -> [T] {
		try ModelContext(container).fetch(FetchDescriptor<T>())
	}

	// MARK: - Receptions

	@Test("A packet records the radio that received it, once per packet")
	func receptionRecorded() async throws {
		let container = try makeContainer()
		let packets = await makePackets(container)
		let broadcast = packet(id: 42, from: remote, snr: 6, hopStart: 3, hopLimit: 1)
		await packets.recordReception(packet: broadcast, radioNum: radioA)
		await packets.recordReception(packet: broadcast, radioNum: radioA)
		await packets.savePendingChanges(caller: "test")
		let rows = try fetch(PacketReceptionEntity.self, in: container)
		#expect(rows.count == 1)
		#expect(rows.first?.radioNum == radioA)
		#expect(rows.first?.snr == 6)
		#expect(rows.first?.hopsAway == 2)
	}

	@Test("A copy the radio couldn't decrypt records nothing")
	func undecryptedCopyNotRecorded() async throws {
		let container = try makeContainer()
		let packets = await makePackets(container)
		var encrypted = MeshPacket()
		encrypted.id = 43
		encrypted.from = UInt32(remote)
		encrypted.encrypted = Data([1, 2, 3])
		await packets.recordReception(packet: encrypted, radioNum: radioA)
		await packets.savePendingChanges(caller: "test")
		#expect(try fetch(PacketReceptionEntity.self, in: container).isEmpty)
	}

	// MARK: - Observations and messages

	@Test("With one radio the node is written as before and mirrored in its observation")
	func singleRadioObservation() async throws {
		let container = try makeContainer()
		try seedNodes([remote], in: container)
		let packets = await makePackets(container)

		await packets.updateAnyPacketFrom(packet: packet(id: 1, from: remote, snr: 6, hopStart: 3, hopLimit: 1), activeDeviceNum: radioA)
		// No hop information: hops stay what they were, as before.
		await packets.updateAnyPacketFrom(packet: packet(id: 2, from: remote, snr: 4), activeDeviceNum: radioA)
		await packets.savePendingChanges()

		let node = try #require(try fetch(NodeInfoEntity.self, in: container).first)
		#expect(node.hopsAway == 2)
		#expect(node.snr == 4)
		#expect(node.lastHeard == Date(timeIntervalSince1970: 1_800_000_000))
		let observation = try #require(try fetch(NodeObservationEntity.self, in: container).first)
		#expect(observation.radioNum == radioA)
		#expect(observation.hopsAway == 2)
		#expect(observation.snr == 4)
	}

	@Test("An evicted node's observations go with it")
	func evictionDeletesObservations() async throws {
		let container = try makeContainer()
		let kept: Int64 = 0x5555
		try seedNodes([remote, kept], in: container)
		let context = ModelContext(container)
		for node in try context.fetch(FetchDescriptor<NodeInfoEntity>()) where node.num == kept {
			node.lastHeard = .now
		}
		for num in [remote, kept] {
			context.insert(NodeObservationEntity(radioNum: radioA, nodeNum: num))
			context.insert(NodeObservationEntity(radioNum: radioB, nodeNum: num))
		}
		try context.save()
		let packets = await makePackets(container)

		#expect(await packets.evictNodesIfOverCap(1) == 1)
		await packets.savePendingChanges()

		let left = try fetch(NodeObservationEntity.self, in: container)
		#expect(Set(left.map(\.nodeNum)) == [kept])
		#expect(left.count == 2)
	}

	@Test("Purging stale nodes deletes their observations")
	func purgeDeletesObservations() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let stale = NodeInfoEntity()
		stale.num = remote
		stale.lastHeard = Date(timeIntervalSinceNow: -40 * 86_400)
		context.insert(stale)
		context.insert(NodeObservationEntity(radioNum: radioA, nodeNum: remote))
		context.insert(NodeObservationEntity(radioNum: radioB, nodeNum: remote))
		try context.save()
		let packets = await makePackets(container)

		#expect(await packets.clearStaleNodes(nodeExpireDays: 30))

		#expect(try fetch(NodeInfoEntity.self, in: container).isEmpty)
		#expect(try fetch(NodeObservationEntity.self, in: container).isEmpty)
	}

	@Test("A radio's node database fills its observation")
	func nodeDBObservation() async throws {
		let container = try makeContainer()
		let packets = await makePackets(container)
		var info = NodeInfo()
		info.num = UInt32(remote)
		info.snr = 3
		info.hopsAway = 2
		info.isFavorite = true
		info.lastHeard = 1_800_000_000

		_ = await packets.nodeInfoPacket(nodeInfo: info, channel: 0, connectedNodeNum: radioA)
		await packets.savePendingChanges()

		let observation = try #require(try fetch(NodeObservationEntity.self, in: container).first)
		#expect(observation.key == NodeObservationEntity.key(radioNum: radioA, nodeNum: remote))
		#expect(observation.hopsAway == 2)
		#expect(observation.snr == 3)
		#expect(observation.favorite)
		#expect(observation.lastHeard == Date(timeIntervalSince1970: 1_800_000_000))
	}
}

// MARK: - Messages

extension MultiRadioIngestTests {

	@Test("A received message gets its sender, recipient, local radio and key")
	func messageColumns() async throws {
		let container = try makeContainer()
		try seedNodes([remote, radioA], in: container)
		let packets = await makePackets(container)

		await packets.textMessageAppPacket(packet: packet(id: 7, from: remote, to: UInt32(radioA), text: "dm"), wantRangeTestPackets: false, connectedNode: radioA, appState: nil)
		await packets.savePendingChanges()

		let message = try #require(try fetch(MessageEntity.self, in: container).first)
		#expect(message.fromNum == remote)
		#expect(message.toNum == radioA)
		#expect(message.localNodeNum == radioA)
		#expect(message.channelKey == nil)
		#expect(message.messageKey == MessageEntity.key(fromNum: remote, messageId: 7))
	}

	@Test("Two senders that pick the same packet id both keep their message")
	func sharedPacketIdAcrossSenders() async throws {
		let container = try makeContainer()
		let other: Int64 = 0x0000_5555
		try seedNodes([remote, other, radioA], in: container)
		let packets = await makePackets(container)

		await packets.textMessageAppPacket(packet: packet(id: 11, from: remote, text: "one"), wantRangeTestPackets: false, connectedNode: radioA, appState: nil)
		await packets.savePendingChanges()
		await packets.textMessageAppPacket(packet: packet(id: 11, from: other, text: "two"), wantRangeTestPackets: false, connectedNode: radioA, appState: nil)
		await packets.savePendingChanges()

		let messages = try fetch(MessageEntity.self, in: container)
		#expect(Set(messages.compactMap(\.messageKey)) == [
			MessageEntity.key(fromNum: remote, messageId: 11),
			MessageEntity.key(fromNum: other, messageId: 11)
		])
	}

	@Test("Stored positions and telemetry carry their packet id")
	func packetIdsAreStored() async throws {
		let container = try makeContainer()
		try seedNodes([remote], in: container)
		let packets = await makePackets(container)

		var position = Position()
		position.latitudeI = 400_000_000
		position.longitudeI = -1_050_000_000
		position.time = 1_800_000_000
		var positionPacket = packet(id: 51, from: remote)
		positionPacket.decoded.payload = try position.serializedData()
		await packets.upsertPositionPacket(packet: positionPacket)

		var telemetry = Telemetry()
		var metrics = DeviceMetrics()
		metrics.batteryLevel = 80
		telemetry.deviceMetrics = metrics
		var telemetryPacket = packet(id: 52, from: remote)
		telemetryPacket.decoded.portnum = .telemetryApp
		telemetryPacket.decoded.payload = try telemetry.serializedData()
		await packets.telemetryPacket(packet: telemetryPacket, connectedNode: radioA)
		await packets.savePendingChanges()

		#expect(try fetch(PositionEntity.self, in: container).map(\.packetId) == [51])
		#expect(try fetch(TelemetryEntity.self, in: container).map(\.packetId) == [52])
	}
}
