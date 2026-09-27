//
//  MultiRadioBackfillTests.swift
//  MeshtasticTests
//
//  Feature 021: the backfill fills the new columns on rows an older build stored, and the
//  reception prune keeps the table inside its retention.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Multi-radio backfill")
@MainActor
struct MultiRadioBackfillTests {

	private let ownRadio: Int64 = 0x0A0A_0A0A
	private let remote: Int64 = 0x1234_5678

	// MARK: - Helpers

	private func makeContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"MultiRadioBackfillTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		let container = try ModelContainer(for: schema, configurations: config)
		let context = ModelContext(container)
		context.autosaveEnabled = false
		return context
	}

	@discardableResult
	private func makeUser(_ num: Int64, in context: ModelContext) -> UserEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		context.insert(node)
		let user = UserEntity()
		user.num = num
		user.userNode = node
		context.insert(user)
		return user
	}

	/// The store's own radio on LongFast, with a default primary and a private secondary.
	private func makeOwnRadio(in context: ModelContext) -> (user: UserEntity, myInfo: MyInfoEntity) {
		let user = makeUser(ownRadio, in: context)
		let lora = LoRaConfigEntity()
		lora.usePreset = true
		lora.modemPreset = Int32(Config.LoRaConfig.ModemPreset.longFast.rawValue)
		context.insert(lora)
		user.userNode?.loRaConfig = lora
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = ownRadio
		myInfo.myInfoNode = user.userNode
		context.insert(myInfo)
		let primary = ChannelEntity()
		primary.index = 0
		primary.psk = Data([1])
		primary.role = Int32(Channel.Role.primary.rawValue)
		primary.myInfoChannel = myInfo
		context.insert(primary)
		let secondary = ChannelEntity()
		secondary.index = 1
		secondary.name = "Hikers"
		secondary.psk = Data(repeating: 7, count: 32)
		secondary.role = Int32(Channel.Role.secondary.rawValue)
		secondary.myInfoChannel = myInfo
		context.insert(secondary)
		return (user, myInfo)
	}

	private func drain(_ context: ModelContext, ownRadio: Int64, chunkSize: Int = 500) throws -> Int {
		var chunks = 0
		while try MultiRadioBackfill.runChunk(in: context, ownRadio: ownRadio, chunkSize: chunkSize).total > 0 {
			chunks += 1
			guard chunks < 100 else { Issue.record("Backfill did not finish"); break }
		}
		return chunks
	}

	// MARK: - Channels and messages

	@Test("Channels get the same key the firmware rules give")
	func channelsGetKeys() throws {
		let context = try makeContext()
		let own = makeOwnRadio(in: context)
		try context.save()

		_ = try drain(context, ownRadio: ownRadio)

		let primary = try #require(own.myInfo.channels.first { $0.index == 0 })
		let expected = ChannelIdentity.key(
			name: nil, psk: Data([1]), isSecondary: false,
			usePreset: true, modemPreset: Int32(Config.LoRaConfig.ModemPreset.longFast.rawValue)
		)
		#expect(primary.channelKey == expected)
		#expect(primary.channelKey?.hasSuffix(":LongFast") == true)
		let secondary = try #require(own.myInfo.channels.first { $0.index == 1 })
		#expect(secondary.channelKey?.hasSuffix(":Hikers") == true)
	}

	@Test("Old messages get numbers, keys, the store's radio and their channel")
	func messagesAreFilled() throws {
		let context = try makeContext()
		let own = makeOwnRadio(in: context)
		let other = makeUser(remote, in: context)

		let channelMessage = MessageEntity()
		channelMessage.messageId = 1
		channelMessage.channel = 1
		channelMessage.fromUser = other
		context.insert(channelMessage)
		let directIn = MessageEntity()
		directIn.messageId = 2
		directIn.fromUser = other
		directIn.toUser = own.user
		context.insert(directIn)
		let directOut = MessageEntity()
		directOut.messageId = 3
		directOut.fromUser = own.user
		directOut.toUser = other
		context.insert(directOut)
		let orphan = MessageEntity()
		orphan.messageId = 4
		context.insert(orphan)
		try context.save()

		_ = try drain(context, ownRadio: ownRadio)

		let secondaryKey = try #require(own.myInfo.channels.first { $0.index == 1 }?.channelKey)
		#expect(channelMessage.fromNum == remote)
		#expect(channelMessage.toNum == MultiRadioBackfill.broadcastNum)
		#expect(channelMessage.channelKey == secondaryKey)
		#expect(channelMessage.localNodeNum == ownRadio)
		#expect(channelMessage.messageKey == MessageEntity.key(fromNum: remote, messageId: 1))

		#expect(directIn.toNum == ownRadio)
		#expect(directIn.channelKey == nil)
		#expect(directIn.localNodeNum == ownRadio)
		#expect(directOut.fromNum == ownRadio)
		#expect(directOut.toNum == remote)
		#expect(directOut.messageKey == MessageEntity.key(fromNum: ownRadio, messageId: 3))

		// Visited, but with no sender there is no key to give it.
		#expect(orphan.fromNum == 0)
		#expect(orphan.messageKey == nil)
	}

	@Test("Rows that already have values keep them")
	func existingValuesArePreserved() throws {
		let context = try makeContext()
		_ = makeOwnRadio(in: context)
		let other = makeUser(remote, in: context)
		let message = MessageEntity()
		message.messageId = 9
		message.fromUser = other
		message.localNodeNum = 0x0B0B_0B0B
		message.channelKey = "c1:open:Elsewhere"
		context.insert(message)
		try context.save()

		_ = try drain(context, ownRadio: ownRadio)

		#expect(message.localNodeNum == 0x0B0B_0B0B)
		#expect(message.channelKey == "c1:open:Elsewhere")
		#expect(message.fromNum == remote)
	}

	@Test("With no radio yet, messages still get sender keys but no local radio")
	func noOwnRadio() throws {
		let context = try makeContext()
		let other = makeUser(remote, in: context)
		let message = MessageEntity()
		message.messageId = 5
		message.fromUser = other
		context.insert(message)
		try context.save()

		_ = try drain(context, ownRadio: 0)

		#expect(message.messageKey == MessageEntity.key(fromNum: remote, messageId: 5))
		#expect(message.localNodeNum == nil)
		#expect(try context.fetchCount(FetchDescriptor<NodeObservationEntity>()) == 0)
	}

	// MARK: - Observations

	@Test("Each node gets the store radio's observation, copied from its fields")
	func observationsAreCreated() throws {
		let context = try makeContext()
		_ = makeOwnRadio(in: context)
		let other = makeUser(remote, in: context)
		let node = try #require(other.userNode)
		node.hopsAway = 3
		node.snr = 2.5
		node.rssi = -100
		node.favorite = true
		node.sessionPasskey = Data([9])
		try context.save()

		_ = try drain(context, ownRadio: ownRadio)

		let rows = try context.fetch(FetchDescriptor<NodeObservationEntity>())
		// None for the radio itself.
		#expect(rows.count == 1)
		let observation = try #require(rows.first)
		#expect(observation.key == NodeObservationEntity.key(radioNum: ownRadio, nodeNum: remote))
		#expect(observation.hopsAway == 3)
		#expect(observation.snr == 2.5)
		#expect(observation.rssi == -100)
		#expect(observation.favorite)
		#expect(observation.sessionPasskey == Data([9]))
	}

	@Test("No observations are copied once another radio has its own")
	func observationsStopWithAnotherRadio() throws {
		let context = try makeContext()
		_ = makeOwnRadio(in: context)
		makeUser(remote, in: context)
		let secondRadio: Int64 = 0x0B0B_0B0B
		makeUser(0x3333, in: context)
		context.insert(NodeObservationEntity(radioNum: secondRadio, nodeNum: 0x3333))
		try context.save()

		_ = try drain(context, ownRadio: ownRadio)

		let rows = try context.fetch(FetchDescriptor<NodeObservationEntity>())
		#expect(rows.map(\.radioNum) == [secondRadio])
	}

	@Test("A store with old rows is backfilled in one go, attributed to the radio given")
	func drainsAtOnce() async throws {
		let context = try makeContext()
		_ = makeOwnRadio(in: context)
		let other = makeUser(remote, in: context)
		for id in 1...30 {
			let message = MessageEntity()
			message.messageId = Int64(id)
			message.fromUser = other
			context.insert(message)
		}
		try context.save()
		let packets = MeshPackets(modelContainer: context.container)
		#expect(await packets.hasPendingBackfill())

		let filled = try await packets.drainMultiRadioBackfill(ownRadio: ownRadio)

		#expect(filled >= 30)
		#expect(await !packets.hasPendingBackfill())
		let rows = try ModelContext(context.container).fetch(FetchDescriptor<MessageEntity>())
		#expect(rows.allSatisfy { $0.localNodeNum == ownRadio })
	}

	@Test("The backfill works in chunks and stops once everything is filled")
	func resumesInChunks() throws {
		let context = try makeContext()
		_ = makeOwnRadio(in: context)
		let other = makeUser(remote, in: context)
		for id in 1...25 {
			let message = MessageEntity()
			message.messageId = Int64(id)
			message.fromUser = other
			context.insert(message)
		}
		for num in 1...12 { makeUser(Int64(0x2000 + num), in: context) }
		try context.save()

		let chunks = try drain(context, ownRadio: ownRadio, chunkSize: 10)
		#expect(chunks == 3)
		#expect(try context.fetchCount(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.fromNum == nil })) == 0)
		#expect(try context.fetchCount(FetchDescriptor<NodeObservationEntity>()) == 13)
		#expect(try MultiRadioBackfill.runChunk(in: context, ownRadio: ownRadio).total == 0)
	}

	// MARK: - Reception retention

	@Test("Receptions older than the retention window are pruned")
	func pruneByAge() throws {
		let context = try makeContext()
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		for (id, days) in [(1, 40.0), (2, 31.0), (3, 29.0), (4, 1.0)] {
			let reception = PacketReceptionEntity(radioNum: ownRadio, fromNum: remote, packetId: Int64(id))
			reception.rxTime = now.addingTimeInterval(-days * 86_400)
			context.insert(reception)
		}
		let undated = PacketReceptionEntity(radioNum: ownRadio, fromNum: remote, packetId: 5)
		context.insert(undated)
		try context.save()

		while try PacketReceptionEntity.prune(in: context, now: now) > 0 { try context.save() }
		try context.save()

		let kept = Set(try context.fetch(FetchDescriptor<PacketReceptionEntity>()).map(\.packetId))
		#expect(kept == [3, 4, 5])
	}

	@Test("Receptions over the row limit are pruned oldest first")
	func pruneByCount() throws {
		let context = try makeContext()
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		for id in 1...10 {
			let reception = PacketReceptionEntity(radioNum: ownRadio, fromNum: remote, packetId: Int64(id))
			reception.rxTime = now.addingTimeInterval(Double(id) - 100)
			context.insert(reception)
		}
		try context.save()

		while try PacketReceptionEntity.prune(in: context, now: now, rowLimit: 4, limit: 3) > 0 { try context.save() }
		try context.save()

		let kept = try context.fetch(FetchDescriptor<PacketReceptionEntity>()).map(\.packetId).sorted()
		#expect(kept == [7, 8, 9, 10])
	}
}
