//
//  ChannelConversations.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import CryptoKit
import Foundation
import MeshtasticProtobufs
import OSLog
@preconcurrency import SwiftData

/// A channel as the firmware sees it: its effective name and its effective key. Two channels
/// that differ in either are different conversations. Region is not part of it.
struct ChannelIdentity: Hashable, Sendable {
	let name: String
	let psk: Data

	/// The key the firmware uses on the air, from the key stored in the channel settings.
	///
	/// An empty key and the one byte `0x00` mean no encryption. Any other one byte value is an
	/// index into the well known default key: `0x01` is the default key and each step above adds
	/// one to its last byte. A short key is padded with zeros to the next AES size.
	static func effectivePSK(_ psk: Data) -> Data {
		switch psk.count {
		case 0:
			return Data()
		case 1:
			let index = psk[psk.startIndex]
			guard index > 0 else { return Data() }
			var key = defaultPSK
			key[key.count - 1] = key[key.count - 1] &+ (index - 1)
			return key
		case 2..<16:
			return psk + Data(count: 16 - psk.count)
		case 17..<32:
			return psk + Data(count: 32 - psk.count)
		default:
			return psk
		}
	}

	/// A blank channel name takes the modem preset's name, the same way the firmware names it.
	/// A custom LoRa configuration has no preset, so it is "Custom" whatever its settings.
	static func effectiveName(_ name: String?, usePreset: Bool, modemPreset: Int32) -> String {
		if let name, !name.isEmpty { return name }
		guard usePreset else { return "Custom" }
		return (ModemPresets(rawValue: Int(modemPreset)) ?? .longFast).androidChannelName
	}

	static let defaultPSK = Data([
		0xD4, 0xF1, 0xBB, 0x3A, 0x20, 0x29, 0x07, 0x59,
		0xF0, 0xBC, 0xFF, 0xAB, 0xCF, 0x4E, 0x69, 0x01
	])

	init(name: String?, psk: Data?, usePreset: Bool, modemPreset: Int32) {
		self.name = Self.effectiveName(name, usePreset: usePreset, modemPreset: modemPreset)
		self.psk = Self.effectivePSK(psk ?? Data())
	}

	/// A one way digest of the identity, so stored records never carry the key.
	var token: String {
		var hasher = SHA256()
		hasher.update(data: Data(name.utf8))
		hasher.update(data: Data([0]))
		hasher.update(data: psk)
		return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
	}
}

/// One enabled slot on the radio and the channel in it.
struct ChannelConversationSlot: Equatable, Sendable {
	let index: Int32
	let token: String
	let name: String
}

/// What the app knows about the conversation stored under one key.
struct ChannelConversationRecord: Equatable, Hashable, Sendable {
	let key: Int32
	let token: String
	let name: String
	var archivedAt: Date?
}

/// The changes that bring stored conversations in line with the radio's channel set.
struct ChannelConversationPlan: Equatable, Sendable {
	/// Where the broadcast messages and reactions stored under a key go. Covers archiving,
	/// moving to another slot and coming back from the archive.
	var broadcastMoves: [Int32: Int32] = [:]
	/// Where direct messages stored under a slot go. Only a channel that moves to another slot
	/// takes them along; a direct message is never archived.
	var directMoves: [Int32: Int32] = [:]
	/// Every record once the plan is applied.
	var records: [ChannelConversationRecord] = []

	var movesMessages: Bool { !broadcastMoves.isEmpty || !directMoves.isEmpty }
}

enum ChannelConversations {

	/// Stand-ins handed to the conversation screen, one per archive key, so a selection keeps
	/// its identity across list refreshes. Never inserted into a context: the store's channel
	/// rows are only ever the radio's own.
	@MainActor private static var archivedChannels: [Int32: ChannelEntity] = [:]

	/// An unsaved channel carrying an archive's key and name, which is what the conversation
	/// screen reads its messages and title from.
	@MainActor
	static func archivedChannel(for record: ChannelConversationRecord) -> ChannelEntity {
		// Read from view bodies, so it only writes when something changed: a write to an
		// observed model during a body evaluation schedules another one.
		if let channel = archivedChannels[record.key] {
			if channel.name != record.name { channel.name = record.name }
			return channel
		}
		let channel = ChannelEntity()
		channel.id = record.key
		channel.index = record.key
		channel.name = record.name
		channel.role = Int32(Channel.Role.secondary.rawValue)
		archivedChannels[record.key] = channel
		return channel
	}

	/// The channel a notification's reply or tapback goes out on: the one the message it answers
	/// is stored under now. The notification carries the slot the message arrived on, which is
	/// stale once its channel moves, while reconciling moves the message along. nil when the
	/// message is gone or its conversation is archived, so nothing is sent.
	static func replyChannel(forMessageId messageId: Int64, in context: ModelContext) -> Int32? {
		var descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == messageId })
		descriptor.fetchLimit = 1
		guard let message = try? context.fetch(descriptor).first, message.channel >= 0 else {
			Logger.services.info("💬 Not answering message \(messageId, privacy: .public) from a notification: its channel is no longer on the radio")
			return nil
		}
		return message.channel
	}

	/// Archived conversations that still hold messages, newest archive first. Copied out as
	/// values: the records are rewritten on another context, and a view holding one of those
	/// objects after it was deleted there would trap on its next read.
	@MainActor
	static func archivedConversations(in context: ModelContext) -> [ChannelConversationRecord] {
		let descriptor = FetchDescriptor<ChannelConversationEntity>(
			predicate: #Predicate { $0.key < 0 },
			sortBy: [SortDescriptor(\.key)]
		)
		let records = ((try? context.fetch(descriptor)) ?? []).map {
			ChannelConversationRecord(key: $0.key, token: $0.token, name: $0.name, archivedAt: $0.archivedAt)
		}
		return records.filter { record in
			let key = record.key
			var messages = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.channel == key && $0.isEmoji == false })
			messages.fetchLimit = 1
			return ((try? context.fetchCount(messages)) ?? 0) > 0
		}
	}

	/// The slots to reconcile against, or nil when the set can't support that conclusion yet:
	/// without a primary channel or the LoRa configuration a blank name resolves through, a
	/// channel that looks gone may simply not have arrived.
	static func slots(channels: [ChannelEntity], usePreset: Bool?, modemPreset: Int32) -> [ChannelConversationSlot]? {
		guard let usePreset else { return nil }
		let enabled = channels.filter { $0.role != Int32(Channel.Role.disabled.rawValue) }
		guard enabled.contains(where: { $0.index == 0 }) else { return nil }
		var byIndex: [Int32: ChannelConversationSlot] = [:]
		for channel in enabled where (0..<8).contains(channel.index) {
			let identity = ChannelIdentity(
				name: channel.name,
				psk: channel.psk,
				usePreset: usePreset,
				modemPreset: modemPreset
			)
			byIndex[channel.index] = ChannelConversationSlot(index: channel.index, token: identity.token, name: identity.name)
		}
		return byIndex.values.sorted { $0.index < $1.index }
	}

	/// Pairs the stored conversations with the radio's slots, one to one.
	///
	/// A channel that stayed put keeps its slot. A channel that moved takes its conversation
	/// along. A channel that is back gets its archived conversation again. A conversation whose
	/// channel is gone is archived. Two slots can hold the same identity, so each record is
	/// paired at most once and nothing is ever merged.
	///
	/// With no records yet this only records what each slot holds. Messages already stored are
	/// left alone, because there is no telling which channel they were on.
	static func plan(
		records: [ChannelConversationRecord],
		slots: [ChannelConversationSlot],
		now: Date = .now
	) -> ChannelConversationPlan {
		let slotRecords = slots.map { ChannelConversationRecord(key: $0.index, token: $0.token, name: $0.name) }
		var live = records.filter { $0.key >= 0 }
		guard !live.isEmpty else {
			return ChannelConversationPlan(records: slotRecords + records.filter { $0.key < 0 })
		}
		var archived = records.filter { $0.key < 0 }
		var plan = ChannelConversationPlan()
		var unpaired: [ChannelConversationSlot] = []

		// A channel still in its own slot.
		for slot in slots {
			if let match = live.firstIndex(where: { $0.key == slot.index && $0.token == slot.token }) {
				live.remove(at: match)
			} else {
				unpaired.append(slot)
			}
		}

		for slot in unpaired {
			// A channel that moved to another slot.
			if let match = live.filter({ $0.token == slot.token }).min(by: { $0.key < $1.key }),
			   let position = live.firstIndex(of: match) {
				live.remove(at: position)
				plan.broadcastMoves[match.key] = slot.index
				plan.directMoves[match.key] = slot.index
			// A channel that came back. The newest archive of it is the one it left most recently.
			} else if let match = archived.filter({ $0.token == slot.token }).min(by: { $0.key < $1.key }),
					  let position = archived.firstIndex(of: match) {
				archived.remove(at: position)
				plan.broadcastMoves[match.key] = slot.index
			}
			// Otherwise a channel the app hasn't seen: its conversation starts empty.
		}

		// What is left of the old set has left the radio. Archive keys count down from -1.
		var nextArchiveKey = min(records.map(\.key).min() ?? 0, 0) - 1
		var newArchives: [ChannelConversationRecord] = []
		for record in live.sorted(by: { $0.key < $1.key }) {
			plan.broadcastMoves[record.key] = nextArchiveKey
			newArchives.append(ChannelConversationRecord(key: nextArchiveKey, token: record.token, name: record.name, archivedAt: now))
			nextArchiveKey -= 1
		}

		plan.records = slotRecords + archived + newArchives
		return plan
	}
}

extension MeshPackets {

	/// Brings stored conversations in line with the radio's channel set and returns the ids of
	/// the messages it archived.
	///
	/// Runs on this actor because it is the one that writes messages, so a packet arriving
	/// mid-reconcile cannot land under a key that is about to move.
	func reconcileChannelConversations(slots: [ChannelConversationSlot]) -> [Int64] {
		do {
			let stored = try modelContext.fetch(FetchDescriptor<ChannelConversationEntity>())
			let records = stored.map {
				ChannelConversationRecord(key: $0.key, token: $0.token, name: $0.name, archivedAt: $0.archivedAt)
			}
			let plan = ChannelConversations.plan(records: records, slots: slots)
			guard plan.movesMessages || Set(plan.records) != Set(records) else { return [] }

			var archivedMessageIDs: [Int64] = []
			if plan.movesMessages {
				let keys = Array(Set(plan.broadcastMoves.keys).union(plan.directMoves.keys))
				let descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { keys.contains($0.channel) })
				// Every message is fetched under its old key before any is changed, so a swap
				// or a slot vacated and refilled in the same plan cannot carry one set twice.
				// toUser is checked in Swift: a nil comparison on it in a #Predicate crashes.
				for message in try modelContext.fetch(descriptor) {
					let target = message.toUser == nil ? plan.broadcastMoves[message.channel] : plan.directMoves[message.channel]
					guard let target else { continue }
					if target < 0 { archivedMessageIDs.append(message.messageId) }
					message.channel = target
				}
			}
			// Updated in place where the key survives, so a row is only deleted when its
			// conversation really is gone.
			var storedByKey: [Int32: ChannelConversationEntity] = [:]
			for entity in stored {
				if storedByKey[entity.key] == nil {
					storedByKey[entity.key] = entity
				} else {
					modelContext.delete(entity)
				}
			}
			for record in plan.records {
				if let entity = storedByKey.removeValue(forKey: record.key) {
					if entity.token != record.token { entity.token = record.token }
					if entity.name != record.name { entity.name = record.name }
					if entity.archivedAt != record.archivedAt { entity.archivedAt = record.archivedAt }
				} else {
					modelContext.insert(ChannelConversationEntity(key: record.key, token: record.token, name: record.name, archivedAt: record.archivedAt))
				}
			}
			for entity in storedByKey.values {
				modelContext.delete(entity)
			}
			try modelContext.save()
			if plan.movesMessages {
				Logger.data.info("💬 Reconciled channel conversations: \(plan.broadcastMoves.count, privacy: .public) moved, \(archivedMessageIDs.count, privacy: .public) message(s) archived")
				Task { @MainActor in
					NotificationCenter.default.post(name: .meshMessagesDidChange, object: nil)
				}
			}
			return archivedMessageIDs
		} catch {
			modelContext.rollback()
			Logger.data.error("💥 Could not reconcile channel conversations: \(error.localizedDescription, privacy: .public)")
			return []
		}
	}

	/// Deletes an archived conversation: its messages and its record.
	func deleteArchivedConversation(key: Int32) {
		guard key < 0 else { return }
		do {
			// Fetched and deleted one by one, as deleteChannelMessages does: messages have
			// inverse relationships that a batch delete has to nullify in the same save.
			for message in try modelContext.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.channel == key })) {
				modelContext.delete(message)
			}
			for record in try modelContext.fetch(FetchDescriptor<ChannelConversationEntity>(predicate: #Predicate { $0.key == key })) {
				modelContext.delete(record)
			}
			try modelContext.save()
			Task { @MainActor in
				NotificationCenter.default.post(name: .meshMessagesDidChange, object: nil)
			}
		} catch {
			modelContext.rollback()
			Logger.data.error("💥 Could not delete archived conversation: \(error.localizedDescription, privacy: .public)")
		}
	}
}

extension AccessoryManager {

	/// Reconciles conversations against the connected radio's stored channel set. Pass
	/// `loRaConfig` when a LoRa save has not reached the store's copy yet.
	@MainActor
	func reconcileChannelConversations(loRaConfig: Config.LoRaConfig? = nil) async {
		guard let nodeNum = activeConnection?.device.num ?? activeDeviceNum,
			  let node = getNodeInfo(id: nodeNum, context: context),
			  let myInfo = node.myInfo else { return }
		let usePreset = loRaConfig?.usePreset ?? node.loRaConfig?.usePreset
		let modemPreset = loRaConfig.map { Int32($0.modemPreset.rawValue) } ?? node.loRaConfig?.modemPreset ?? 0
		guard let slots = ChannelConversations.slots(channels: myInfo.channels, usePreset: usePreset, modemPreset: modemPreset) else { return }
		let archivedMessageIDs = await MeshPackets.shared.reconcileChannelConversations(slots: slots)
		if !archivedMessageIDs.isEmpty {
			// A notification for a message that is now archived would offer a reply onto
			// whatever channel holds its old slot.
			LocalNotificationManager().cancelNotificationsForMessageIds(archivedMessageIDs)
		}
	}
}
