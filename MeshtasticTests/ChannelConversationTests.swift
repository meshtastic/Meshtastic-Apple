//
//  ChannelConversationTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Channel identity")
struct ChannelIdentityTests {

	@Test func oneBytePSKExpandsToTheDefaultKey() {
		#expect(ChannelIdentity.effectivePSK(Data([1])) == ChannelIdentity.defaultPSK)
		var second = ChannelIdentity.defaultPSK
		second[15] = 0x02
		#expect(ChannelIdentity.effectivePSK(Data([2])) == second)
	}

	@Test func zeroAndEmptyPSKAreBothCleartext() {
		#expect(ChannelIdentity.effectivePSK(Data([0])).isEmpty)
		#expect(ChannelIdentity.effectivePSK(Data()).isEmpty)
	}

	@Test func shortKeysArePaddedToAnAESSize() {
		#expect(ChannelIdentity.effectivePSK(Data([1, 2, 3])).count == 16)
		#expect(ChannelIdentity.effectivePSK(Data(repeating: 7, count: 20)).count == 32)
	}

	@Test func blankNameTakesThePresetName() {
		let longFast = ChannelIdentity(name: "", psk: Data([1]), usePreset: true, modemPreset: Int32(ModemPresets.longFast.rawValue))
		let mediumSlow = ChannelIdentity(name: nil, psk: Data([1]), usePreset: true, modemPreset: Int32(ModemPresets.medSlow.rawValue))
		#expect(longFast.name == "LongFast")
		#expect(mediumSlow.name == "MediumSlow")
		#expect(longFast.token != mediumSlow.token)
	}

	@Test func namedChannelIgnoresThePreset() {
		let first = ChannelIdentity(name: "Hikers", psk: Data([1]), usePreset: true, modemPreset: Int32(ModemPresets.longFast.rawValue))
		let second = ChannelIdentity(name: "Hikers", psk: Data([1]), usePreset: true, modemPreset: Int32(ModemPresets.shortFast.rawValue))
		#expect(first.token == second.token)
	}

	@Test func customLoRaIsNamedCustom() {
		#expect(ChannelIdentity(name: "", psk: Data([1]), usePreset: false, modemPreset: 0).name == "Custom")
	}

	@Test func storedOneByteMarkerMatchesTheExpandedKey() {
		let marker = ChannelIdentity(name: "Ops", psk: Data([1]), usePreset: true, modemPreset: 0)
		let expanded = ChannelIdentity(name: "Ops", psk: ChannelIdentity.defaultPSK, usePreset: true, modemPreset: 0)
		#expect(marker.token == expanded.token)
	}

	@Test func tokenDoesNotCarryTheKey() {
		let identity = ChannelIdentity(name: "Ops", psk: Data(repeating: 0xAB, count: 32), usePreset: true, modemPreset: 0)
		#expect(identity.token.count == 16)
		#expect(!identity.token.contains("abababab"))
	}
}

@Suite("Channel conversation plan")
struct ChannelConversationPlanTests {

	private func slot(_ index: Int32, _ name: String) -> ChannelConversationSlot {
		ChannelConversationSlot(index: index, token: "t-\(name)", name: name)
	}

	private func record(_ key: Int32, _ name: String) -> ChannelConversationRecord {
		ChannelConversationRecord(key: key, token: "t-\(name)", name: name)
	}

	private let now = Date(timeIntervalSince1970: 1_000)

	@Test func firstRunOnlyRecordsTheSlots() {
		let plan = ChannelConversations.plan(records: [], slots: [slot(0, "A"), slot(1, "B")], now: now)
		#expect(!plan.movesMessages)
		#expect(Set(plan.records) == [record(0, "A"), record(1, "B")])
	}

	@Test func unchangedSetMovesNothing() {
		let records = [record(0, "A"), record(1, "B")]
		let plan = ChannelConversations.plan(records: records, slots: [slot(0, "A"), slot(1, "B")], now: now)
		#expect(!plan.movesMessages)
		#expect(Set(plan.records) == Set(records))
	}

	@Test func replacedChannelIsArchived() {
		let plan = ChannelConversations.plan(records: [record(0, "A"), record(1, "B")], slots: [slot(0, "A"), slot(1, "C")], now: now)
		#expect(plan.broadcastMoves == [1: -1])
		#expect(plan.directMoves.isEmpty)
		#expect(plan.records.contains(ChannelConversationRecord(key: -1, token: "t-B", name: "B", archivedAt: now)))
		#expect(plan.records.contains(record(1, "C")))
	}

	@Test func swappedChannelsTakeTheirConversations() {
		let plan = ChannelConversations.plan(records: [record(0, "A"), record(1, "B"), record(2, "C")], slots: [slot(0, "A"), slot(1, "C"), slot(2, "B")], now: now)
		#expect(plan.broadcastMoves == [1: 2, 2: 1])
		#expect(plan.directMoves == [1: 2, 2: 1])
	}

	@Test func deletingTheFirstOfTwoArchivesItAndShiftsTheSecond() {
		let plan = ChannelConversations.plan(records: [record(0, "P"), record(1, "A"), record(2, "B")], slots: [slot(0, "P"), slot(1, "B")], now: now)
		#expect(plan.broadcastMoves == [1: -1, 2: 1])
		#expect(plan.directMoves == [2: 1])
	}

	@Test func returningChannelGetsItsArchiveBack() {
		let archived = ChannelConversationRecord(key: -1, token: "t-B", name: "B", archivedAt: now)
		let plan = ChannelConversations.plan(records: [record(0, "A"), record(1, "C"), archived], slots: [slot(0, "A"), slot(1, "B")], now: now)
		#expect(plan.broadcastMoves == [-1: 1, 1: -2])
		#expect(!plan.records.contains(archived))
		#expect(plan.records.contains(record(1, "B")))
	}

	@Test func duplicateIdentitiesArePairedOnce() {
		let plan = ChannelConversations.plan(records: [record(0, "A"), record(1, "X")], slots: [slot(0, "A"), slot(1, "A")], now: now)
		// Slot 0 keeps its conversation and slot 1's A starts empty rather than merging.
		#expect(plan.broadcastMoves == [1: -1])
	}

	@Test func archiveKeysNeverCollide() {
		let older = ChannelConversationRecord(key: -3, token: "t-Z", name: "Z", archivedAt: now)
		let plan = ChannelConversations.plan(records: [record(0, "A"), record(1, "B"), older], slots: [slot(0, "A")], now: now)
		#expect(plan.broadcastMoves == [1: -4])
	}

	@Test func newestArchiveIsReclaimedFirst() {
		let older = ChannelConversationRecord(key: -1, token: "t-B", name: "B", archivedAt: now)
		let newer = ChannelConversationRecord(key: -2, token: "t-B", name: "B", archivedAt: now)
		let plan = ChannelConversations.plan(records: [record(0, "A"), older, newer], slots: [slot(0, "A"), slot(1, "B")], now: now)
		#expect(plan.broadcastMoves == [-2: 1])
		#expect(plan.records.contains(older))
	}
}

@Suite("Channel conversation reconcile", .serialized)
struct ChannelConversationReconcileTests {

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"ChannelConversationTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return try ModelContainer(for: schema, configurations: config)
	}

	private func slot(_ index: Int32, _ name: String) -> ChannelConversationSlot {
		let identity = ChannelIdentity(name: name, psk: Data([1]), usePreset: true, modemPreset: 0)
		return ChannelConversationSlot(index: index, token: identity.token, name: identity.name)
	}

	@discardableResult
	private func insertMessage(
		_ context: ModelContext,
		id: Int64,
		channel: Int32,
		emojiFor replyID: Int64 = 0,
		to user: UserEntity? = nil
	) -> MessageEntity {
		let message = MessageEntity()
		message.messageId = id
		message.channel = channel
		message.messagePayload = "message \(id)"
		message.isEmoji = replyID > 0
		message.replyID = replyID
		message.toUser = user
		context.insert(message)
		return message
	}

	private func channels(_ context: ModelContext) throws -> [Int64: Int32] {
		let messages = try context.fetch(FetchDescriptor<MessageEntity>())
		return Dictionary(uniqueKeysWithValues: messages.map { ($0.messageId, $0.channel) })
	}

	@Test func replaceArchivesAndReturnBringsBackWithReactions() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		insertMessage(context, id: 1, channel: 1)
		insertMessage(context, id: 2, channel: 1, emojiFor: 1)
		try context.save()
		let mesh = MeshPackets(modelContainer: container)

		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "Old")])
		let archived = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "New")])
		#expect(Set(archived) == [1, 2])
		#expect(try channels(ModelContext(container)) == [1: -1, 2: -1])

		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "Old")])
		#expect(try channels(ModelContext(container)) == [1: 1, 2: 1])
	}

	@Test func directMessagesAreNeverArchived() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let user = UserEntity()
		user.num = 42
		context.insert(user)
		insertMessage(context, id: 1, channel: 1, to: user)
		insertMessage(context, id: 2, channel: 1)
		try context.save()
		let mesh = MeshPackets(modelContainer: container)

		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "Old")])
		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "New")])
		#expect(try channels(ModelContext(container)) == [1: 1, 2: -1])
	}

	@Test func survivorShiftsIntoTheRemovedSlot() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		insertMessage(context, id: 1, channel: 1)
		insertMessage(context, id: 2, channel: 2)
		try context.save()
		let mesh = MeshPackets(modelContainer: container)

		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "A"), slot(2, "B")])
		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "B")])
		#expect(try channels(ModelContext(container)) == [1: -1, 2: 1])
	}

	@Test func reconnectingWithTheSameChannelsChangesNothing() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		insertMessage(context, id: 1, channel: 0)
		insertMessage(context, id: 2, channel: 1)
		try context.save()
		let mesh = MeshPackets(modelContainer: container)
		let slots = [slot(0, "P"), slot(1, "A")]

		for _ in 0..<3 {
			#expect(await mesh.reconcileChannelConversations(slots: slots).isEmpty)
		}
		#expect(try channels(ModelContext(container)) == [1: 0, 2: 1])
		#expect(try ModelContext(container).fetchCount(FetchDescriptor<ChannelConversationEntity>()) == 2)
	}

	@Test func firstReconcileLeavesExistingMessagesWhereTheyAre() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		insertMessage(context, id: 1, channel: 1)
		try context.save()
		let mesh = MeshPackets(modelContainer: container)

		#expect(await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "Anything")]).isEmpty)
		#expect(try channels(ModelContext(container)) == [1: 1])
	}

	@Test func notificationActionsFollowTheMessageToItsChannel() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		insertMessage(context, id: 1, channel: 1)
		insertMessage(context, id: 2, channel: 2)
		try context.save()
		let mesh = MeshPackets(modelContainer: container)

		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "A"), slot(2, "B")])
		// A leaves and B shifts into slot 1: a notification for message 2 still says slot 2.
		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "B")])
		let reader = ModelContext(container)
		#expect(ChannelConversations.replyChannel(forMessageId: 2, in: reader) == 1)
		#expect(ChannelConversations.replyChannel(forMessageId: 1, in: reader) == nil)
		#expect(ChannelConversations.replyChannel(forMessageId: 99, in: reader) == nil)
	}

	@Test func deletingAnArchiveRemovesItsMessagesAndRecord() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		insertMessage(context, id: 1, channel: 1)
		insertMessage(context, id: 2, channel: 0)
		try context.save()
		let mesh = MeshPackets(modelContainer: container)

		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P"), slot(1, "Old")])
		_ = await mesh.reconcileChannelConversations(slots: [slot(0, "P")])
		await mesh.deleteArchivedConversation(key: -1)
		let check = ModelContext(container)
		#expect(try channels(check) == [2: 0])
		#expect(try check.fetchCount(FetchDescriptor<ChannelConversationEntity>(predicate: #Predicate { $0.key < 0 })) == 0)
	}
}
