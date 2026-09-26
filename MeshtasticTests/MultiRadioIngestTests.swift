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

@Suite("Multi-radio ingest")
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

	@Test("Receptions tell a first delivery, a repeat and another radio's delivery apart")
	func receptionOutcomes() async throws {
		let container = try makeContainer()
		let packets = await makePackets(container)
		let broadcast = packet(id: 42, from: remote)

		#expect(await packets.recordReception(packet: broadcast, radioNum: radioA) == .first)
		// Unsaved: the lookup must see the pending row too.
		#expect(await packets.recordReception(packet: broadcast, radioNum: radioA) == .repeatFromSameRadio)
		#expect(await packets.recordReception(packet: broadcast, radioNum: radioB) == .heardByAnotherRadio)
		#expect(await packets.recordReception(packet: packet(id: 0, from: remote), radioNum: radioA) == .untracked)
		// Another sender's packet with the same id is a different packet.
		#expect(await packets.recordReception(packet: packet(id: 42, from: 0x55), radioNum: radioB) == .first)

		await packets.savePendingChanges()
		let rows = try fetch(PacketReceptionEntity.self, in: container)
		#expect(rows.count == 3)
		#expect(Set(rows.filter { $0.fromNum == remote }.map(\.radioNum)) == [radioA, radioB])
	}

	// MARK: - Observations

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

	@Test("With two radios the node shows the best path and each radio keeps its own view")
	func twoRadioAggregate() async throws {
		let container = try makeContainer()
		try seedNodes([remote], in: container)
		let packets = await makePackets(container)

		await packets.updateAnyPacketFrom(packet: packet(id: 1, from: remote, snr: -10, hopStart: 3, hopLimit: 0), activeDeviceNum: radioA)
		await packets.updateAnyPacketFrom(packet: packet(id: 1, from: remote, snr: 7, hopStart: 3, hopLimit: 2), activeDeviceNum: radioB)
		// A later, worse reception by A must not replace B's better path on the node.
		await packets.updateAnyPacketFrom(packet: packet(id: 2, from: remote, snr: -12, hopStart: 3, hopLimit: 0), activeDeviceNum: radioA)
		await packets.savePendingChanges()

		let node = try #require(try fetch(NodeInfoEntity.self, in: container).first)
		#expect(node.hopsAway == 1)
		#expect(node.snr == 7)
		let observations = try fetch(NodeObservationEntity.self, in: container)
		#expect(observations.count == 2)
		#expect(observations.first { $0.radioNum == radioA }?.hopsAway == 3)
		#expect(observations.first { $0.radioNum == radioA }?.snr == -12)
		#expect(observations.first { $0.radioNum == radioB }?.hopsAway == 1)
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

	// MARK: - Messages

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

	@Test("The same broadcast through two radios is stored once")
	func sameBroadcastTwoRadios() async throws {
		let container = try makeContainer()
		try seedNodes([remote, radioA, radioB], in: container)
		let packets = await makePackets(container)
		let broadcast = packet(id: 9, from: remote, text: "hello")

		await packets.textMessageAppPacket(packet: broadcast, wantRangeTestPackets: false, connectedNode: radioA, appState: nil)
		await packets.savePendingChanges()
		await packets.textMessageAppPacket(packet: broadcast, wantRangeTestPackets: false, connectedNode: radioB, appState: nil)
		await packets.savePendingChanges()

		let messages = try fetch(MessageEntity.self, in: container)
		#expect(messages.count == 1)
		#expect(messages.first?.localNodeNum == radioA)
		#expect(messages.first?.toNum == MultiRadioBackfill.broadcastNum)
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

	// MARK: - Positions, telemetry, admin sessions

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

	@Test("Each radio keeps its own admin session with a node")
	func adminSessionsPerRadio() async throws {
		let container = try makeContainer()
		try seedNodes([remote], in: container)
		let packets = await makePackets(container)

		await packets.recordAdminSession(passkey: Data([1]), nodeNum: remote, radioNum: radioA)
		await packets.recordAdminSession(passkey: Data([2]), nodeNum: remote, radioNum: radioB)
		// A radio has no admin session with itself.
		await packets.recordAdminSession(passkey: Data([3]), nodeNum: radioA, radioNum: radioA)
		await packets.savePendingChanges()

		let observations = try fetch(NodeObservationEntity.self, in: container)
		#expect(observations.count == 2)
		#expect(observations.first { $0.radioNum == radioA }?.sessionPasskey == Data([1]))
		#expect(observations.first { $0.radioNum == radioB }?.sessionPasskey == Data([2]))
		#expect(observations.allSatisfy { $0.sessionExpiration != nil })
	}

	// MARK: - Notifications

	/// Both radios known to the store, each with an unmuted primary channel.
	private func seedTwoRadios(in container: ModelContainer) throws {
		try seedNodes([remote, radioA, radioB], in: container)
		let context = ModelContext(container)
		for radio in [radioA, radioB] {
			let channel = ChannelEntity()
			channel.index = 0
			channel.name = "Primary"
			context.insert(channel)
			let myInfo = MyInfoEntity()
			myInfo.myNodeNum = radio
			myInfo.channels = [channel]
			context.insert(myInfo)
		}
		try context.save()
	}

	private func makePackets(_ container: ModelContainer, recording box: MainActorBox<[MeshNotification]>) async -> MeshPackets {
		let packets = MeshPackets(modelContainer: container)
		await packets.replaceNotificationScheduler { @MainActor @Sendable notifications in
			box.value.append(contentsOf: notifications)
		}
		return packets
	}

	@Test("A broadcast from the user's other radio lands read and silent")
	func ownOtherRadioIsSelf() async throws {
		let previous = UserDefaults.channelMessageNotifications
		UserDefaults.channelMessageNotifications = true
		defer { UserDefaults.channelMessageNotifications = previous }
		let container = try makeContainer()
		try seedTwoRadios(in: container)
		let box = MainActorBox<[MeshNotification]>([])
		let packets = await makePackets(container, recording: box)

		// Sent through radio B (stored by nothing yet, e.g. a store-and-forward replay), heard by A.
		await packets.textMessageAppPacket(packet: packet(id: 31, from: radioB, text: "mine"), wantRangeTestPackets: false, connectedNode: radioA, appState: nil)
		await packets.savePendingChanges()
		try? await Task.sleep(for: .milliseconds(100))

		#expect(box.value.isEmpty)
		#expect(try fetch(MessageEntity.self, in: container).first?.read == true)
	}

	@Test("A peer broadcast heard by two radios notifies once")
	func peerBroadcastNotifiesOnce() async throws {
		let previous = UserDefaults.channelMessageNotifications
		UserDefaults.channelMessageNotifications = true
		defer { UserDefaults.channelMessageNotifications = previous }
		let container = try makeContainer()
		try seedTwoRadios(in: container)
		let box = MainActorBox<[MeshNotification]>([])
		let packets = await makePackets(container, recording: box)
		let broadcast = packet(id: 32, from: remote, text: "hi all")

		await packets.textMessageAppPacket(packet: broadcast, wantRangeTestPackets: false, connectedNode: radioA, appState: nil)
		await packets.savePendingChanges()
		await packets.textMessageAppPacket(packet: broadcast, wantRangeTestPackets: false, connectedNode: radioB, appState: nil)
		await packets.savePendingChanges()
		try? await Task.sleep(for: .milliseconds(100))

		#expect(box.value.count == 1)
	}

	@Test("A sent message and its echo merge on the key")
	func sentMessageMergesWithEcho() async throws {
		let container = try makeContainer()
		try seedNodes([radioA], in: container)
		let context = ModelContext(container)
		let sent = MessageEntity()
		sent.messageId = 21
		sent.fromNum = radioA
		sent.messageKey = MessageEntity.key(fromNum: radioA, messageId: 21)
		sent.read = true
		sent.receivedACK = true
		context.insert(sent)
		try context.save()

		let packets = await makePackets(container)
		await packets.textMessageAppPacket(packet: packet(id: 21, from: radioA, text: "mine"), wantRangeTestPackets: false, connectedNode: radioA, appState: nil)
		await packets.savePendingChanges()

		let messages = try fetch(MessageEntity.self, in: container)
		#expect(messages.count == 1)
		#expect(messages.first?.receivedACK == true)
	}
}
