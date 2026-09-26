//
//  MultiRadioSchemaTests.swift
//  MeshtasticTests
//
//  Feature 021 (multi-radio) schema additions: the new entities and attributes survive a
//  backup restore, follow a node renumber, and the unique keys collapse repeats.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Multi-radio schema")
@MainActor
struct MultiRadioSchemaTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B
	private let remote: Int64 = 0x1234_5678

	// MARK: - Helpers

	private func makeContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"MultiRadioSchemaTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		let container = try ModelContainer(for: schema, configurations: config)
		let context = ModelContext(container)
		context.autosaveEnabled = false
		return context
	}

	private func makeNode(_ num: Int64, in context: ModelContext) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		context.insert(node)
		return node
	}

	// MARK: - Unique keys

	@Test("A second observation for the same radio and node replaces the first")
	func observationKeyIsUnique() throws {
		let context = try makeContext()
		let first = NodeObservationEntity(radioNum: radioA, nodeNum: remote)
		first.snr = 1
		context.insert(first)
		try context.save()

		let second = NodeObservationEntity(radioNum: radioA, nodeNum: remote)
		second.snr = 7
		context.insert(second)
		context.insert(NodeObservationEntity(radioNum: radioB, nodeNum: remote))
		try context.save()

		let rows = try context.fetch(FetchDescriptor<NodeObservationEntity>())
		#expect(rows.count == 2)
		let fromA = try #require(rows.first { $0.radioNum == radioA })
		#expect(fromA.snr == 7)
	}

	@Test("Receptions are unique per radio, sender and packet")
	func receptionKeyIsUnique() throws {
		let context = try makeContext()
		context.insert(PacketReceptionEntity(radioNum: radioA, fromNum: remote, packetId: 99))
		context.insert(PacketReceptionEntity(radioNum: radioB, fromNum: remote, packetId: 99))
		// Another sender may pick the same packet id.
		context.insert(PacketReceptionEntity(radioNum: radioA, fromNum: 0x55, packetId: 99))
		try context.save()
		context.insert(PacketReceptionEntity(radioNum: radioA, fromNum: remote, packetId: 99))
		try context.save()

		#expect(try context.fetchCount(FetchDescriptor<PacketReceptionEntity>()) == 3)
	}

	@Test("Hops away needs a starting hop count from the sender")
	func receptionHopsAway() {
		let reception = PacketReceptionEntity(radioNum: radioA, fromNum: remote, packetId: 1)
		#expect(reception.hopsAway == nil)
		reception.hopStart = 3
		reception.hopLimit = 1
		#expect(reception.hopsAway == 2)
		reception.hopLimit = 5
		#expect(reception.hopsAway == nil)
	}

	@Test("Message keys scope the packet id to its sender")
	func messageKeyFormat() {
		#expect(MessageEntity.key(fromNum: 10, messageId: 20) == "10:20")
		#expect(MessageEntity.key(fromNum: 11, messageId: 20) != MessageEntity.key(fromNum: 10, messageId: 20))
	}

	// MARK: - Backup restore

	@Test("Restore keeps the multi-radio attributes on radios, channels and messages")
	func restoreKeepsNewAttributes() throws {
		let backup = try makeContext()
		let live = try makeContext()
		let when = Date(timeIntervalSince1970: 1_800_000_000)

		let node = makeNode(radioA, in: backup)
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = radioA
		myInfo.myInfoNode = node
		myInfo.lastConnected = when
		myInfo.autoConnect = true
		myInfo.transport = "BLE"
		myInfo.sortOrder = 3
		myInfo.displayColor = "#FF8800"
		backup.insert(myInfo)
		let channel = ChannelEntity()
		channel.index = 1
		channel.channelKey = "c1:abc:Test"
		channel.myInfoChannel = myInfo
		backup.insert(channel)
		let message = MessageEntity()
		message.messageId = 4242
		message.fromNum = remote
		message.toNum = radioA
		message.localNodeNum = radioA
		message.channelKey = "c1:abc:Test"
		message.messageKey = MessageEntity.key(fromNum: remote, messageId: 4242)
		backup.insert(message)
		try backup.save()

		let nodes = try NodeBackupManager.importNodes(from: backup, into: live)
		let users = try NodeBackupManager.importUsers(from: backup, into: live, nodesByNum: nodes)
		let myInfos = try NodeBackupManager.importMyInfo(from: backup, into: live, nodesByNum: nodes)
		try NodeBackupManager.importChannels(from: backup, into: live, myInfosByNodeNum: myInfos)
		try NodeBackupManager.importMessages(from: backup, into: live, usersByNum: users)
		try live.save()

		let dstInfo = try #require(try live.fetch(FetchDescriptor<MyInfoEntity>()).first)
		#expect(dstInfo.lastConnected == when)
		#expect(dstInfo.autoConnect)
		#expect(dstInfo.transport == "BLE")
		#expect(dstInfo.sortOrder == 3)
		#expect(dstInfo.displayColor == "#FF8800")
		let dstChannel = try #require(try live.fetch(FetchDescriptor<ChannelEntity>()).first)
		#expect(dstChannel.channelKey == "c1:abc:Test")
		let dstMessage = try #require(try live.fetch(FetchDescriptor<MessageEntity>()).first)
		#expect(dstMessage.fromNum == remote)
		#expect(dstMessage.toNum == radioA)
		#expect(dstMessage.localNodeNum == radioA)
		#expect(dstMessage.channelKey == "c1:abc:Test")
		#expect(dstMessage.messageKey == "\(remote):4242")
	}

	@Test("Restore keeps packet ids on positions and telemetry")
	func restoreKeepsPacketIds() throws {
		let backup = try makeContext()
		let live = try makeContext()
		let node = makeNode(remote, in: backup)
		let position = PositionEntity()
		position.packetId = 111
		position.nodePosition = node
		backup.insert(position)
		let telemetry = TelemetryEntity()
		telemetry.packetId = 222
		telemetry.nodeTelemetry = node
		backup.insert(telemetry)
		try backup.save()

		let nodes = try NodeBackupManager.importNodes(from: backup, into: live)
		try NodeBackupManager.importPositions(from: backup, into: live, nodesByNum: nodes)
		try NodeBackupManager.importTelemetry(from: backup, into: live, nodesByNum: nodes)
		try live.save()

		#expect(try live.fetch(FetchDescriptor<PositionEntity>()).first?.packetId == 111)
		#expect(try live.fetch(FetchDescriptor<TelemetryEntity>()).first?.packetId == 222)
	}

	@Test("Restore copies observations and receptions field by field")
	func restoreKeepsNewEntities() throws {
		let backup = try makeContext()
		let live = try makeContext()
		let when = Date(timeIntervalSince1970: 1_800_000_000)

		let observation = NodeObservationEntity(radioNum: radioA, nodeNum: remote)
		observation.firstHeard = when
		observation.lastHeard = when.addingTimeInterval(60)
		observation.hopsAway = 2
		observation.snr = 4.5
		observation.rssi = -90
		observation.viaMqtt = true
		observation.channel = 1
		observation.favorite = true
		observation.ignored = true
		observation.isKeyManuallyVerified = true
		observation.sessionPasskey = Data([1, 2, 3])
		observation.sessionExpiration = when.addingTimeInterval(300)
		backup.insert(observation)

		let reception = PacketReceptionEntity(radioNum: radioB, fromNum: remote, packetId: 77)
		reception.toNum = radioB
		reception.portNum = 1
		reception.channel = 2
		reception.rxTime = when
		reception.snr = -3
		reception.rssi = -110
		reception.hopStart = 3
		reception.hopLimit = 2
		reception.relayNode = 0x78
		reception.viaMqtt = true
		backup.insert(reception)
		try backup.save()

		try NodeBackupManager.importNodeObservations(from: backup, into: live)
		try NodeBackupManager.importPacketReceptions(from: backup, into: live)
		try live.save()

		let dstObservation = try #require(try live.fetch(FetchDescriptor<NodeObservationEntity>()).first)
		#expect(dstObservation.key == NodeObservationEntity.key(radioNum: radioA, nodeNum: remote))
		#expect(dstObservation.firstHeard == when)
		#expect(dstObservation.lastHeard == when.addingTimeInterval(60))
		#expect(dstObservation.hopsAway == 2)
		#expect(dstObservation.snr == 4.5)
		#expect(dstObservation.rssi == -90)
		#expect(dstObservation.viaMqtt)
		#expect(dstObservation.channel == 1)
		#expect(dstObservation.favorite)
		#expect(dstObservation.ignored)
		#expect(dstObservation.isKeyManuallyVerified)
		#expect(dstObservation.sessionPasskey == Data([1, 2, 3]))
		#expect(dstObservation.sessionExpiration == when.addingTimeInterval(300))

		let dstReception = try #require(try live.fetch(FetchDescriptor<PacketReceptionEntity>()).first)
		#expect(dstReception.key == PacketReceptionEntity.key(radioNum: radioB, fromNum: remote, packetId: 77))
		#expect(dstReception.toNum == radioB)
		#expect(dstReception.portNum == 1)
		#expect(dstReception.channel == 2)
		#expect(dstReception.rxTime == when)
		#expect(dstReception.snr == -3)
		#expect(dstReception.rssi == -110)
		#expect(dstReception.hopStart == 3)
		#expect(dstReception.hopLimit == 2)
		#expect(dstReception.relayNode == 0x78)
		#expect(dstReception.viaMqtt)
	}

	// MARK: - Node renumber

	@Test("Renumbering a radio moves its observations, receptions and message columns")
	func renumberMovesMultiRadioRows() throws {
		let context = try makeContext()
		let newA: Int64 = 0x0C0C_0C0C
		_ = makeNode(radioA, in: context)

		context.insert(NodeObservationEntity(radioNum: radioA, nodeNum: remote))
		context.insert(NodeObservationEntity(radioNum: radioB, nodeNum: radioA))
		let reception = PacketReceptionEntity(radioNum: radioA, fromNum: remote, packetId: 5)
		reception.toNum = radioA
		context.insert(reception)
		context.insert(PacketReceptionEntity(radioNum: radioB, fromNum: radioA, packetId: 6))
		let sent = MessageEntity()
		sent.messageId = 1
		sent.fromNum = radioA
		sent.toNum = remote
		sent.localNodeNum = radioA
		sent.messageKey = MessageEntity.key(fromNum: radioA, messageId: 1)
		context.insert(sent)
		let received = MessageEntity()
		received.messageId = 2
		received.fromNum = remote
		received.toNum = radioA
		received.localNodeNum = radioA
		received.messageKey = MessageEntity.key(fromNum: remote, messageId: 2)
		context.insert(received)
		try context.save()

		#expect(NodeRenumber.apply(from: radioA, to: newA, in: context))

		let keys = Set(try context.fetch(FetchDescriptor<NodeObservationEntity>()).map(\.key))
		#expect(keys == [
			NodeObservationEntity.key(radioNum: newA, nodeNum: remote),
			NodeObservationEntity.key(radioNum: radioB, nodeNum: newA)
		])
		let receptions = try context.fetch(FetchDescriptor<PacketReceptionEntity>())
		#expect(Set(receptions.map(\.key)) == [
			PacketReceptionEntity.key(radioNum: newA, fromNum: remote, packetId: 5),
			PacketReceptionEntity.key(radioNum: radioB, fromNum: newA, packetId: 6)
		])
		#expect(receptions.first { $0.packetId == 5 }?.toNum == newA)

		let messages = try context.fetch(FetchDescriptor<MessageEntity>())
		let dstSent = try #require(messages.first { $0.messageId == 1 })
		#expect(dstSent.fromNum == newA)
		#expect(dstSent.localNodeNum == newA)
		#expect(dstSent.messageKey == MessageEntity.key(fromNum: newA, messageId: 1))
		let dstReceived = try #require(messages.first { $0.messageId == 2 })
		#expect(dstReceived.toNum == newA)
		#expect(dstReceived.localNodeNum == newA)
		#expect(dstReceived.messageKey == MessageEntity.key(fromNum: remote, messageId: 2))
	}

	@Test("An observation already under the new number gives way to the old one")
	func renumberFoldsCollidingObservation() throws {
		let context = try makeContext()
		let newA: Int64 = 0x0C0C_0C0C
		_ = makeNode(radioA, in: context)
		let old = NodeObservationEntity(radioNum: radioA, nodeNum: remote)
		old.favorite = true
		context.insert(old)
		let stale = NodeObservationEntity(radioNum: newA, nodeNum: remote)
		stale.favorite = false
		context.insert(stale)
		try context.save()

		#expect(NodeRenumber.apply(from: radioA, to: newA, in: context))

		let rows = try context.fetch(FetchDescriptor<NodeObservationEntity>())
		#expect(rows.count == 1)
		#expect(rows.first?.key == NodeObservationEntity.key(radioNum: newA, nodeNum: remote))
		#expect(rows.first?.favorite == true)
	}
}
