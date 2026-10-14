//
//  ChannelChangeEventsTests.swift
//  MeshtasticTests
//
//  Feature 021 (T377, T382): a radio's channel slot keeps its conversation when the radio moves it
//  to another channel, with a change row between the history before and after, and channel keys
//  are read as saved.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Channel change rows")
struct ChannelChangeEventsTests {

	let radioA: Int64 = 0x0A0A_0A0A
	let radioB: Int64 = 0x0B0B_0B0B
	let longFast = Int32(Config.LoRaConfig.ModemPreset.longFast.rawValue)
	let longTurbo = Int32(Config.LoRaConfig.ModemPreset.longTurbo.rawValue)

	func makeContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("ChannelChangeEventsTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		return ModelContext(try ModelContainer(for: schema, configurations: config))
	}

	/// A radio on `preset` with the default unnamed primary and the given named secondaries.
	@discardableResult
	func makeRadio(_ num: Int64, preset: Int32, secondaries: [Int32: String] = [:], in context: ModelContext) -> MyInfoEntity {
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

	func setPreset(_ preset: Int32, on radio: MyInfoEntity, at seconds: Int, in context: ModelContext) throws {
		radio.myInfoNode?.loRaConfig?.modemPreset = preset
		try MultiRadioBackfill.updateChannelKeys(for: radio.myNodeNum, in: context, now: Date(timeIntervalSince1970: TimeInterval(seconds)))
		try context.save()
	}

	func key(of radio: MyInfoEntity, slot: Int32) throws -> String {
		try #require(radio.channels.first { $0.index == slot }?.channelKey)
	}

	func insertMessage(_ id: Int64, at seconds: Int32, key: String, radio: Int64, in context: ModelContext) {
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

	/// The conversation for `radio`'s slot 0 as the channel list reads it (by slot), oldest first:
	/// real messages by id, change rows as "event".
	func thread(in context: ModelContext) throws -> [String] {
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate { $0.channel == 0 && $0.isEmoji == false },
			sortBy: [SortDescriptor(\.messageTimestamp)]
		)
		return try context.fetch(descriptor)
			.filter { $0.toUser == nil }
			.map { $0.isSystemEvent ? "event" : String($0.messageId) }
	}

	@Test("A radio that switches preset keeps its history, with a change row between")
	func presetSwitchKeepsHistory() throws {
		let context = try makeContext()
		let radio = makeRadio(radioA, preset: longFast, in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		try context.save()
		let longFastKey = try key(of: radio, slot: 0)
		for id in Int64(1)...5 {
			insertMessage(id, at: Int32(id), key: longFastKey, radio: radioA, in: context)
		}
		try context.save()

		try setPreset(longTurbo, on: radio, at: 10, in: context)
		let longTurboKey = try key(of: radio, slot: 0)
		#expect(longTurboKey != longFastKey)
		#expect(longTurboKey.hasSuffix(":LongTurbo"))
		insertMessage(6, at: 11, key: longTurboKey, radio: radioA, in: context)
		try context.save()

		#expect(try thread(in: context) == ["1", "2", "3", "4", "5", "event", "6"])
		let event = try #require(try ChannelChangeEvents.latestEvent(radio: radioA, slot: 0, in: context))
		#expect(ChannelChangeDescription.text(previous: event.previousChannelKey, current: event.channelKey) == "Switched from LongFast to LongTurbo.")
		#expect(event.read)
		#expect(event.fromNum == 0)
	}

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

	@Test("Filling in a missing key isn't a change of channel")
	func backfillLeavesNoRow() throws {
		let context = try makeContext()
		makeRadio(radioA, preset: longFast, secondaries: [1: "Hikers"], in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		#expect(try context.fetch(FetchDescriptor<MessageEntity>()).isEmpty)
	}

	@Test("A completed discovery scan leaves the slot's key and no row")
	func completedScanKeepsTheKey() throws {
		let context = try makeContext()
		let scanning: Int64 = 0x0E0E_0E0E
		let radio = makeRadio(scanning, preset: longFast, in: context)
		try MultiRadioBackfill.updateChannelKeys(for: scanning, in: context)
		try context.save()
		let home = try key(of: radio, slot: 0)

		ChannelChangeEvents.pause(radio: scanning)
		try setPreset(longTurbo, on: radio, at: 10, in: context)
		// Messages during the scan still get the scan preset's key...
		let scanKeys = try MultiRadioBackfill.channelKeysByIndex(for: scanning, in: context)
		#expect(scanKeys[0]?.hasSuffix(":LongTurbo") == true)
		// ...but the conversation stays on the home channel.
		#expect(try key(of: radio, slot: 0) == home)
		try setPreset(longFast, on: radio, at: 20, in: context)
		ChannelChangeEvents.resume(radio: scanning)

		try setPreset(longFast, on: radio, at: 30, in: context)
		#expect(try key(of: radio, slot: 0) == home)
		#expect(try context.fetch(FetchDescriptor<MessageEntity>()).isEmpty)
	}

	@Test("A backup restore keeps a change row's fields")
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

	@Test("A change row is never unread")
	@MainActor
	func changeRowsStayOutOfCounts() throws {
		let context = try makeContext()
		let radio = makeRadio(radioA, preset: longFast, in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		try context.save()
		try setPreset(longTurbo, on: radio, at: 10, in: context)
		let primary = try #require(radio.channels.first { $0.index == 0 })
		#expect(primary.unreadMessages(context: context) == 0)
		#expect(try thread(in: context) == ["event"])
	}
}

/// Channel keys read as saved, not from a long-lived context's older copies (T382, T383).
@Suite("Channel keys read as saved across contexts")
struct ChannelChangeStaleContextTests {
	private let base = ChannelChangeEventsTests()
	private var radioA: Int64 { base.radioA }
	private var radioB: Int64 { base.radioB }
	private var longFast: Int32 { base.longFast }
	private var longTurbo: Int32 { base.longTurbo }

	private func makeContext() throws -> ModelContext { try base.makeContext() }

	@discardableResult
	private func makeRadio(_ num: Int64, preset: Int32, secondaries: [Int32: String] = [:], in context: ModelContext) -> MyInfoEntity {
		base.makeRadio(num, preset: preset, secondaries: secondaries, in: context)
	}

	private func setPreset(_ preset: Int32, on radio: MyInfoEntity, at seconds: Int, in context: ModelContext) throws {
		try base.setPreset(preset, on: radio, at: seconds, in: context)
	}

	private func key(of radio: MyInfoEntity, slot: Int32) throws -> String { try base.key(of: radio, slot: slot) }

	private func insertMessage(_ id: Int64, at seconds: Int32, key: String, radio: Int64, in context: ModelContext) {
		base.insertMessage(id, at: seconds, key: key, radio: radio, in: context)
	}

	@Test("The same change seen again from an older key leaves no second row")
	func staleChangeIsNotRecordedTwice() throws {
		let context = try makeContext()
		let at = { (seconds: Int) in Date(timeIntervalSince1970: TimeInterval(seconds)) }
		#expect(try ChannelChangeEvents.record(radio: radioA, slot: 0, from: "c2:lf:k:", to: "c2:lt:k:", in: context, now: at(100)) == 1)
		// A context that still had the LongFast key commits the radio's channels a minute later.
		#expect(try ChannelChangeEvents.record(radio: radioA, slot: 0, from: "c2:lf:k:", to: "c2:lt:k:", in: context, now: at(200)) == 0)
		#expect(try context.fetch(FetchDescriptor<MessageEntity>()).filter(\.isSystemEvent).count == 1)
	}

	@Test("A LoRa change ingested after a rename saved elsewhere keeps the new name's key")
	func actorDoesNotWriteBackARenamedChannel() async throws {
		let context = try makeContext()
		makeRadio(radioA, preset: longFast, secondaries: [1: "Hikers"], in: context)
		try MultiRadioBackfill.updateChannelKeys(for: radioA, in: context)
		try context.save()
		let packets = MeshPackets(modelContainer: context.container)
		var lora = Config.LoRaConfig()
		lora.usePreset = true
		lora.modemPreset = .longFast
		// The actor loads A's channels into its own context.
		await packets.upsertLoRaConfigPacket(config: lora, nodeNum: radioA)

		// The Channels editor (main context) renames slot 1 and saves.
		let editor = ModelContext(context.container)
		let hikers = try #require(try editor.fetch(FetchDescriptor<ChannelEntity>()).first { $0.index == 1 })
		hikers.name = "Bikers"
		try editor.save()
		try MultiRadioBackfill.updateSavedChannelKeys(for: radioA, container: context.container, now: Date(timeIntervalSince1970: 100))

		// Then the radio's LoRa config arrives with a new preset.
		lora.modemPreset = .longTurbo
		await packets.upsertLoRaConfigPacket(config: lora, nodeNum: radioA)

		let stored = MultiRadioBackfill.storedChannelKeys(for: radioA, container: context.container)
		#expect(stored[1]?.hasSuffix(":Bikers") == true)
		#expect(stored[1].flatMap(ChannelIdentity.parts(of:))?.modemPreset == longTurbo)
		// No row puts "Hikers" back.
		let rows = try ModelContext(context.container).fetch(FetchDescriptor<MessageEntity>()).filter { $0.isSystemEvent && $0.channel == 1 }
		#expect(!rows.contains { $0.channelKey?.hasSuffix(":Hikers") == true })
	}

	@Test("The backfill removes a change row recorded twice")
	func duplicateRowsRemoved() throws {
		let context = try makeContext()
		let at = { (seconds: Int) in Date(timeIntervalSince1970: TimeInterval(seconds)) }
		try ChannelChangeEvents.record(radio: radioA, slot: 0, from: "c2:lf:k:", to: "c2:lt:k:", in: context, now: at(100))
		// The duplicate as stores written before the fix have it.
		let duplicate = MessageEntity()
		duplicate.systemEvent = MessageEntity.SystemEvent.channelChanged.rawValue
		duplicate.messageId = -2
		duplicate.messageTimestamp = 160
		duplicate.channel = 0
		duplicate.previousChannelKey = "c2:lf:k:"
		duplicate.channelKey = "c2:lt:k:"
		duplicate.localNodeNum = radioA
		context.insert(duplicate)
		// Another radio's row with the same keys isn't a duplicate.
		try ChannelChangeEvents.record(radio: radioB, slot: 0, from: "c2:lf:k:", to: "c2:lt:k:", in: context, now: at(170))
		// A real change back and forth stays.
		try ChannelChangeEvents.record(radio: radioA, slot: 0, from: "c2:lt:k:", to: "c2:lf:k:", in: context, now: at(500))
		try ChannelChangeEvents.record(radio: radioA, slot: 0, from: "c2:lf:k:", to: "c2:lt:k:", in: context, now: at(900))
		try context.save()

		#expect(try MultiRadioBackfill.removeDuplicateChangeRows(in: context) == 1)
		let left = try context.fetch(FetchDescriptor<MessageEntity>()).filter(\.isSystemEvent)
		#expect(left.count == 4)
		#expect(!left.contains { $0.messageId == -2 })
		#expect(try MultiRadioBackfill.removeDuplicateChangeRows(in: context) == 0)
	}
}
