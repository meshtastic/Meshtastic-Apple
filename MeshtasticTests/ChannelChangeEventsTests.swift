//
//  ChannelChangeEventsTests.swift
//  MeshtasticTests
//
//  Feature 021 (T377–T379): a radio's channel slot keeps its conversation when the radio moves it
//  to another channel, with a change row between the history before and after, and a channel's
//  identity includes the mesh.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Channel change rows and slot history")
struct ChannelChangeEventsTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B
	private let longFast = Int32(Config.LoRaConfig.ModemPreset.longFast.rawValue)
	private let longTurbo = Int32(Config.LoRaConfig.ModemPreset.longTurbo.rawValue)

	private func makeContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("ChannelChangeEventsTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		return ModelContext(try ModelContainer(for: schema, configurations: config))
	}

	/// A radio on `preset` with the default unnamed primary and the given named secondaries.
	@discardableResult
	private func makeRadio(_ num: Int64, preset: Int32, secondaries: [Int32: String] = [:], in context: ModelContext) -> MyInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		context.insert(node)
		let lora = LoRaConfigEntity()
		lora.usePreset = true
		lora.modemPreset = preset
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
		for (index, name) in secondaries {
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

	private func setPreset(_ preset: Int32, on radio: MyInfoEntity, at seconds: Int, in context: ModelContext) throws {
		radio.myInfoNode?.loRaConfig?.modemPreset = preset
		try MultiRadioBackfill.updateChannelKeys(for: radio.myNodeNum, in: context, now: Date(timeIntervalSince1970: TimeInterval(seconds)))
		try context.save()
	}

	private func key(of radio: MyInfoEntity, slot: Int32) throws -> String {
		try #require(radio.channels.first { $0.index == slot }?.channelKey)
	}

	private func insertMessage(_ id: Int64, at seconds: Int32, key: String, radio: Int64, in context: ModelContext) {
		let message = MessageEntity()
		message.messageId = id
		message.messageTimestamp = seconds
		message.channel = 0
		message.channelKey = key
		message.localNodeNum = radio
		message.read = true
		message.messagePayload = "m\(id)"
		context.insert(message)
	}

	/// The thread for `radio`'s slot 0, oldest first: real messages by id, change rows as "event".
	private func thread(of radio: MyInfoEntity, in context: ModelContext) throws -> [String] {
		let current = try key(of: radio, slot: 0)
		let query = ChannelMessageQuery.make(channelIndex: 0, channelKey: current, radioNum: radio.myNodeNum, multiRadio: true, in: context)
		return try ChannelMessageQuery.fetch(query.messages(), limit: nil, in: context)
			.reversed()
			.map { $0.isSystemEvent ? "event" : String($0.messageId) }
	}

	// MARK: - The LongFast → LongTurbo scenario

	@Test("A radio that switches preset keeps its history, with a change row, and the other radio's thread is untouched")
	func presetSwitchKeepsHistory() throws {
		let context = try makeContext()
		let radioAInfo = makeRadio(radioA, preset: longFast, in: context)
		let radioBInfo = makeRadio(radioB, preset: longFast, in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioB, in: context)
		try context.save()
		let longFastKey = try key(of: radioAInfo, slot: 0)
		#expect(try key(of: radioBInfo, slot: 0) == longFastKey)

		// Both radios on LongFast: each message is stored once, under whichever radio heard it first.
		for id in Int64(1)...5 {
			insertMessage(id, at: Int32(id), key: longFastKey, radio: id.isMultiple(of: 2) ? radioB : radioA, in: context)
		}
		try context.save()

		try setPreset(longTurbo, on: radioBInfo, at: 10, in: context)
		let longTurboKey = try key(of: radioBInfo, slot: 0)
		#expect(longTurboKey != longFastKey)
		#expect(longTurboKey.hasSuffix(":LongTurbo"))
		insertMessage(6, at: 11, key: longTurboKey, radio: radioB, in: context)
		// A keeps hearing LongFast while B is away.
		insertMessage(7, at: 50, key: longFastKey, radio: radioA, in: context)
		try context.save()

		// Before the fix, B's thread showed 2 and 4 (the LongFast messages it stored) and 6.
		#expect(try thread(of: radioBInfo, in: context) == ["1", "2", "3", "4", "5", "event", "6"])
		#expect(try thread(of: radioAInfo, in: context) == ["1", "2", "3", "4", "5", "7"])

		let event = try #require(try ChannelChangeEvents.latestEvent(radio: radioB, slot: 0, in: context))
		#expect(ChannelChangeDescription.text(previous: event.previousChannelKey, current: event.channelKey) == "Switched from LongFast to LongTurbo.")
		#expect(event.read)
		#expect(event.fromNum == 0)
	}

	@Test("Switching back continues the thread: each stretch shows the channel the slot had then")
	func switchingBack() throws {
		let context = try makeContext()
		let radioAInfo = makeRadio(radioA, preset: longFast, in: context)
		let radioBInfo = makeRadio(radioB, preset: longFast, in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioB, in: context)
		try context.save()
		let longFastKey = try key(of: radioAInfo, slot: 0)

		insertMessage(1, at: 1, key: longFastKey, radio: radioB, in: context)
		try setPreset(longTurbo, on: radioBInfo, at: 10, in: context)
		let longTurboKey = try key(of: radioBInfo, slot: 0)
		insertMessage(2, at: 20, key: longTurboKey, radio: radioB, in: context)
		// Heard by A while B was on LongTurbo: not B's history.
		insertMessage(3, at: 30, key: longFastKey, radio: radioA, in: context)
		try setPreset(longFast, on: radioBInfo, at: 200, in: context)
		insertMessage(4, at: 210, key: longFastKey, radio: radioA, in: context)
		try context.save()

		#expect(try thread(of: radioBInfo, in: context) == ["1", "event", "2", "event", "4"])
		#expect(try thread(of: radioAInfo, in: context) == ["1", "3", "4"])
	}

	// MARK: - Recording

	@Test("A change undone within the window leaves no row, and a further change extends the row")
	func quickChangesCoalesce() throws {
		let context = try makeContext()
		let at = { (seconds: Int) in Date(timeIntervalSince1970: TimeInterval(seconds)) }

		#expect(try ChannelChangeEvents.record(radio: radioA, slot: 1, from: "c2:x:k:A", to: "c2:x:k:B", in: context, now: at(100)) == 1)
		#expect(try ChannelChangeEvents.record(radio: radioA, slot: 1, from: "c2:x:k:B", to: "c2:x:k:A", in: context, now: at(110)) == 1)
		try context.save()
		#expect(try ChannelChangeEvents.latestEvent(radio: radioA, slot: 1, in: context) == nil)

		try ChannelChangeEvents.record(radio: radioA, slot: 1, from: "c2:x:k:A", to: "c2:x:k:B", in: context, now: at(200))
		try ChannelChangeEvents.record(radio: radioA, slot: 1, from: "c2:x:k:B", to: "c2:x:k:C", in: context, now: at(220))
		let rows = try context.fetch(FetchDescriptor<MessageEntity>()).filter(\.isSystemEvent)
		#expect(rows.count == 1)
		#expect(rows.first?.previousChannelKey == "c2:x:k:A")
		#expect(rows.first?.channelKey == "c2:x:k:C")

		// Outside the window it's a change of its own.
		try ChannelChangeEvents.record(radio: radioA, slot: 1, from: "c2:x:k:C", to: "c2:x:k:D", in: context, now: at(400))
		#expect(try context.fetch(FetchDescriptor<MessageEntity>()).filter(\.isSystemEvent).count == 2)
	}

	@Test("A paused radio's changes (Local Mesh Discovery stepping presets) leave no row")
	func pausedRadioRecordsNothing() throws {
		let context = try makeContext()
		// Its own radio: the pause is app-wide, and the other tests run alongside this one.
		let scanning: Int64 = 0x0D0D_0D0D
		ChannelChangeEvents.pause(radio: scanning)
		defer { ChannelChangeEvents.resume(radio: scanning) }
		#expect(try ChannelChangeEvents.record(radio: scanning, slot: 0, from: "c2:x:k:A", to: "c2:x:k:B", in: context) == 0)
		#expect(try context.fetch(FetchDescriptor<MessageEntity>()).isEmpty)
	}

	@Test("Filling in a missing or c1 key isn't a change of channel")
	func backfillLeavesNoRow() throws {
		let context = try makeContext()
		let radio = makeRadio(radioA, preset: longFast, secondaries: [1: "Hikers"], in: context)
		radio.channels.first { $0.index == 1 }?.channelKey = "c1:abc:Hikers"
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		#expect(try context.fetch(FetchDescriptor<MessageEntity>()).isEmpty)
	}

	// MARK: - Segments

	@Test("Segments follow the change rows, and the last one is the slot's channel now")
	func segmentsFromEvents() {
		#expect(ChannelChangeEvents.segments(events: [], currentKey: "K") == [.init(key: "K", start: nil, end: nil)])
		let segments = ChannelChangeEvents.segments(
			events: [.init(timestamp: 10, previous: "A", key: "B"), .init(timestamp: 20, previous: "B", key: "C")],
			currentKey: "D"
		)
		#expect(segments == [
			.init(key: "A", start: nil, end: 10),
			.init(key: "B", start: 10, end: 20),
			.init(key: "D", start: 20, end: nil)
		])
	}

	// MARK: - Mesh in the identity (T379)

	@Test("A named channel two radios share stops being shared when one moves to another mesh")
	func namedChannelNotSharedAcrossMeshes() throws {
		let context = try makeContext()
		let radioAInfo = makeRadio(radioA, preset: longFast, secondaries: [1: "GoD's"], in: context)
		let radioBInfo = makeRadio(radioB, preset: longFast, secondaries: [2: "GoD's"], in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioB, in: context)
		try context.save()
		let shared = try key(of: radioAInfo, slot: 1)
		#expect(ChannelMessageQuery.slots(for: shared, among: [radioA, radioB], in: context).count == 2)

		try setPreset(longTurbo, on: radioBInfo, at: 10, in: context)
		#expect(ChannelMessageQuery.slots(for: shared, among: [radioA, radioB], in: context) == [ChannelSlot(radio: radioA, index: 1)])
		let event = try #require(try ChannelChangeEvents.latestEvent(radio: radioB, slot: 2, in: context))
		#expect(ChannelChangeDescription.text(previous: event.previousChannelKey, current: event.channelKey) == "Switched from LongFast to LongTurbo.")
	}

	@Test("Messages with a c1 key move to the current key of the channel that has it, else an unknown mesh")
	func legacyMessagesRekeyed() throws {
		let context = try makeContext()
		let radio = makeRadio(radioA, preset: longFast, secondaries: [1: "Hikers"], in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		try context.save()
		let hikers = try #require(radio.channels.first { $0.index == 1 })
		let legacy = hikers.legacyIdentityKey(primaryPSK: Data([1]), usePreset: true, modemPreset: longFast)

		let known = MessageEntity()
		known.messageId = 1
		known.fromNum = 1
		known.channelKey = legacy
		known.localNodeNum = radioA
		context.insert(known)
		let gone = MessageEntity()
		gone.messageId = 2
		gone.fromNum = 1
		gone.channelKey = "c1:open:Elsewhere"
		context.insert(gone)
		let current = MessageEntity()
		current.messageId = 3
		current.fromNum = 1
		current.channelKey = hikers.channelKey
		context.insert(current)
		try context.save()

		#expect(try MultiRadioBackfill.rekeyLegacyMessages(in: context, limit: 10) == 2)
		#expect(known.channelKey == hikers.channelKey)
		#expect(gone.channelKey == "c2:?:open:Elsewhere")
		#expect(current.channelKey == hikers.channelKey)
		#expect(try MultiRadioBackfill.rekeyLegacyMessages(in: context, limit: 10) == 0)
	}

	// MARK: - Where change rows don't count

	@Test("Backup restore and merge keep a change row's fields")
	func backupCopyKeepsChangeRow() throws {
		let context = try makeContext()
		try ChannelChangeEvents.record(radio: radioA, slot: 2, from: "c2:x:k:A", to: "c2:x:k:B", in: context, now: Date(timeIntervalSince1970: 10))
		let row = try #require(try ChannelChangeEvents.latestEvent(radio: radioA, slot: 2, in: context))
		let copy = NodeBackupManager.copied(row)
		#expect(copy.isSystemEvent)
		#expect(copy.systemEvent == row.systemEvent)
		#expect(copy.previousChannelKey == "c2:x:k:A")
		#expect(copy.channelKey == "c2:x:k:B")
		#expect(copy.localNodeNum == radioA)
		#expect(copy.read)
	}

	@Test("A change row is never unread and isn't a reaction or a search result")
	func changeRowsStayOutOfCounts() throws {
		let context = try makeContext()
		let radio = makeRadio(radioA, preset: longFast, in: context)
		makeRadio(radioB, preset: longFast, in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		try context.save()
		try setPreset(longTurbo, on: radio, at: 10, in: context)

		let current = try key(of: radio, slot: 0)
		let query = ChannelMessageQuery.make(channelIndex: 0, channelKey: current, radioNum: radioA, multiRadio: true, in: context)
		#expect(try context.fetch(FetchDescriptor(predicate: query.unreadCandidates())).isEmpty)
		#expect(try ChannelMessageQuery.fetch(query.messages(unreadOnly: true), limit: nil, in: context).isEmpty)
		#expect(try ChannelMessageQuery.fetch(query.messages(), limit: nil, in: context).count == 1)
	}
}
