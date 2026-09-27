//
//  ChannelMessageQueryTests.swift
//  MeshtasticTests
//
//  Feature 021 (T083/T084): a channel is one timeline across radios, grouped by channel key,
//  and each radio sends on it in its own slot.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Channel message query across radios")
struct ChannelMessageQueryTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B
	private let remote: Int64 = 0x1234_5678
	private let hikersKey = "Hikers|key"
	private let otherKey = "Cyclists|key"

	/// A radio on LongFast whose channels are `names` by slot, all with the same private key.
	@discardableResult
	private func makeRadio(_ num: Int64, channels names: [Int32: String], in context: ModelContext) -> MyInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		context.insert(node)
		let lora = LoRaConfigEntity()
		lora.usePreset = true
		lora.modemPreset = Int32(Config.LoRaConfig.ModemPreset.longFast.rawValue)
		context.insert(lora)
		node.loRaConfig = lora
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = num
		myInfo.myInfoNode = node
		context.insert(myInfo)
		let primary = ChannelEntity()
		primary.index = 0
		primary.psk = Data([1])
		primary.role = Int32(Channel.Role.primary.rawValue)
		primary.myInfoChannel = myInfo
		context.insert(primary)
		for (index, name) in names {
			let channel = ChannelEntity()
			channel.index = index
			channel.name = name
			channel.psk = Data(repeating: 7, count: 32)
			channel.role = Int32(Channel.Role.secondary.rawValue)
			channel.myInfoChannel = myInfo
			context.insert(channel)
		}
		return myInfo
	}

	private func makeContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("ChannelMessageQueryTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		return ModelContext(try ModelContainer(for: schema, configurations: config))
	}

	private func insertMessage(_ id: Int64, slot: Int32, key: String?, radio: Int64?, read: Bool = true, emojiReplyTo: Int64? = nil, in context: ModelContext) {
		let message = MessageEntity()
		message.messageId = id
		message.messageTimestamp = Int32(id)
		message.channel = slot
		message.channelKey = key
		message.localNodeNum = radio
		message.read = read
		message.messagePayload = "m\(id)"
		if let emojiReplyTo {
			message.isEmoji = true
			message.replyID = emojiReplyTo
		}
		context.insert(message)
	}

	/// Hikers is slot 1 on radio A and slot 2 on radio B; B has Cyclists in slot 1.
	private func seedMessages(in context: ModelContext) throws {
		insertMessage(1, slot: 1, key: hikersKey, radio: radioA, in: context)
		insertMessage(2, slot: 2, key: hikersKey, radio: radioB, read: false, in: context)
		insertMessage(3, slot: 1, key: otherKey, radio: radioB, in: context)
		insertMessage(4, slot: 1, key: nil, radio: nil, in: context)
		insertMessage(5, slot: 1, key: "Hikers|old", radio: radioA, in: context)
		insertMessage(6, slot: 2, key: nil, radio: radioB, emojiReplyTo: 1, in: context)
		try context.save()
	}

	private func ids(_ rows: [MessageEntity]) -> Set<Int64> {
		Set(rows.map(\.messageId))
	}

	@Test("With several radios, a channel's timeline follows its key across slots")
	func groupedByKey() throws {
		let context = try makeContext()
		try seedMessages(in: context)
		let query = ChannelMessageQuery(channelIndex: 1, channelKey: hikersKey, radioNum: radioA, multiRadio: true)

		let timeline = try ChannelMessageQuery.fetch(query.messages(), limit: nil, in: context)
		// Its key through either radio, plus A's own slot-1 rows (old key, not backfilled);
		// never B's slot 1, which is another channel there.
		#expect(ids(timeline) == [1, 2, 4, 5])
		#expect(ids(try ChannelMessageQuery.fetch(query.messages(unreadOnly: true), limit: nil, in: context)) == [2])
		// The badge's candidates are the same unread rows.
		#expect(ids(try context.fetch(FetchDescriptor(predicate: query.unreadCandidates()))) == [2])
		// A reaction that came through B in B's slot still belongs to the message.
		#expect(ids(try context.fetch(FetchDescriptor(predicate: query.tapbacks(to: [1])))) == [6])
	}

	@Test("With several radios and no key yet, a channel shows only its own radio's slot")
	func keylessChannelStaysOnItsRadio() throws {
		let context = try makeContext()
		try seedMessages(in: context)
		let query = ChannelMessageQuery(channelIndex: 1, channelKey: nil, radioNum: radioA, multiRadio: true)

		// Not 3: B's slot 1 is another channel.
		#expect(ids(try ChannelMessageQuery.fetch(query.messages(), limit: nil, in: context)) == [1, 4, 5])
		let queryB = ChannelMessageQuery(channelIndex: 2, channelKey: nil, radioNum: radioB, multiRadio: true)
		#expect(ids(try context.fetch(FetchDescriptor(predicate: queryB.unreadCandidates()))) == [2])
		#expect(ids(try context.fetch(FetchDescriptor(predicate: queryB.tapbacks(to: [1])))) == [6])
		#expect(ids(try context.fetch(FetchDescriptor(predicate: query.tapbacks(to: [1])))).isEmpty)
	}

	@Test("A radio's channel keys follow its channels and LoRa settings as they arrive")
	func keysSetOnArrival() async throws {
		let context = try makeContext()
		makeRadio(radioA, channels: [1: "Hikers"], in: context)
		try context.save()
		let packets = MeshPackets(modelContainer: context.container)

		var channel = Channel()
		channel.index = 2
		channel.role = .secondary
		channel.settings.name = "Cyclists"
		channel.settings.psk = Data(repeating: 7, count: 32)
		await packets.channelPacket(channel: channel, fromNum: radioA, stageIfRefreshing: false)

		func storedKeys() throws -> [Int32: String?] {
			let rows = try ModelContext(context.container).fetch(FetchDescriptor<ChannelEntity>())
			return Dictionary(uniqueKeysWithValues: rows.map { ($0.index, $0.channelKey) })
		}
		let afterChannel = try storedKeys()
		#expect(afterChannel.count == 3)
		#expect(afterChannel.values.allSatisfy { $0 != nil })

		var lora = Config.LoRaConfig()
		lora.usePreset = true
		lora.modemPreset = .mediumFast
		await packets.upsertLoRaConfigPacket(config: lora, nodeNum: radioA)
		// The unnamed primary is named after the preset, so its key moves; named ones don't.
		let afterLoRa = try storedKeys()
		#expect(afterLoRa[0] != afterChannel[0])
		#expect(afterLoRa[0]??.hasSuffix(":MediumFast") == true)
		#expect(afterLoRa[1] == afterChannel[1])
	}

	@Test("Deleting a channel's messages deletes what its timeline shows")
	func deleteFollowsTimeline() async throws {
		let context = try makeContext()
		try seedMessages(in: context)
		let packets = MeshPackets(modelContainer: context.container)

		await packets.deleteChannelMessages(query: ChannelMessageQuery(channelIndex: 1, channelKey: hikersKey, radioNum: radioA, multiRadio: true))

		// B's Cyclists in slot 1 stays; Hikers through B in slot 2 goes; the tapback stays.
		let left = try ModelContext(context.container).fetch(FetchDescriptor<MessageEntity>())
		#expect(ids(left) == [3, 6])
	}

	@Test("The TAK channel follows its channel to the new TAK radio's slot, or goes to primary")
	@MainActor
	func takChannelMovesWithTheRadio() throws {
		let context = try makeContext()
		makeRadio(radioA, channels: [2: "Team", 3: "Other"], in: context)
		makeRadio(radioB, channels: [1: "Team"], in: context)
		try context.save()

		#expect(TAKServerManager.slot(forChannel: 2, from: radioA, to: radioB, in: context) == 1)
		#expect(TAKServerManager.slot(forChannel: 3, from: radioA, to: radioB, in: context) == 0)
		#expect(TAKServerManager.slot(forChannel: 0, from: radioA, to: radioB, in: context) == 0)
	}

	@Test("With one radio, the timeline is the slot, as before")
	func singleRadio() throws {
		let context = try makeContext()
		try seedMessages(in: context)
		let query = ChannelMessageQuery(channelIndex: 1, channelKey: hikersKey, radioNum: radioA, multiRadio: false)

		#expect(ids(try ChannelMessageQuery.fetch(query.messages(), limit: nil, in: context)) == [1, 3, 4, 5])
		#expect(ids(try context.fetch(FetchDescriptor(predicate: query.tapbacks(to: [1])))).isEmpty)
		#expect(ids(try context.fetch(FetchDescriptor(predicate: query.unreadCandidates()))).isEmpty)
		#expect(!ChannelMessageQuery.isMultiRadio(in: context))
	}

	@Test("Each radio that has the channel sends in its own slot")
	func slotsPerRadio() throws {
		let context = try makeContext()
		makeRadio(radioA, channels: [1: "Hikers"], in: context)
		makeRadio(radioB, channels: [1: "Cyclists", 2: "Hikers"], in: context)
		let radioC: Int64 = 0x0C0C_0C0C
		makeRadio(radioC, channels: [1: "Cyclists"], in: context)
		try context.save()

		let keysA = try MultiRadioBackfill.channelKeysByIndex(for: radioA, in: context, updateStored: false)
		let hikers = try #require(keysA[1])

		let slots = ChannelMessageQuery.slots(for: hikers, among: [radioA, radioB, radioC], in: context)
		#expect(slots == [ChannelSlot(radio: radioA, index: 1), ChannelSlot(radio: radioB, index: 2)])
		#expect(ChannelMessageQuery.isMultiRadio(in: context))
	}
}
