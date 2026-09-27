//
//  MultiRadioBackfill.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import OSLog
import SwiftData

/// Fills the feature-021 columns on rows stored before they existed (plan.md › Schema changes 7).
///
/// Every store written by an older build belongs to exactly one radio: the switch flow keeps one
/// radio's data at a time. That radio (`ownRadio`) is the local radio for every old message and
/// the observer of every old node, so the backfill can fill:
/// - messages: `fromNum`, `toNum`, `messageKey`, `localNodeNum`, and `channelKey` for channel
///   messages;
/// - channels: `channelKey`, from the owning radio's LoRa settings;
/// - observations: one `NodeObservationEntity` per node, copied from the node's own fields,
///   while no other radio has observations.
///
/// It works in chunks and is resumable: a row counts as done once it has its marker (`fromNum`
/// for messages, `channelKey` for channels, an observation for nodes), so an interrupted pass
/// picks up where it stopped. Packet ids on old positions and telemetry are unknown and stay 0.
enum MultiRadioBackfill {
	/// The mesh broadcast address, stored as `toNum` on channel messages.
	static let broadcastNum: Int64 = 0xFFFF_FFFF

	struct ChunkResult: Equatable {
		var channels = 0
		var messages = 0
		var observations = 0

		var total: Int { channels + messages + observations }
	}

	/// Runs one chunk of each step and saves. Returns what it filled; zero means done.
	@discardableResult
	static func runChunk(in context: ModelContext, ownRadio: Int64, chunkSize: Int = 500) throws -> ChunkResult {
		var result = ChunkResult()
		result.channels = try backfillChannels(in: context)
		let channelKeys = try ownRadio == 0 ? [:] : channelKeysByIndex(for: ownRadio, in: context)
		result.messages = try backfillMessages(in: context, ownRadio: ownRadio, channelKeys: channelKeys, limit: chunkSize)
		if ownRadio != 0 {
			result.observations = try backfillObservations(in: context, ownRadio: ownRadio, limit: chunkSize)
		}
		if context.hasChanges {
			try context.save()
		}
		return result
	}

	// MARK: - Channels

	/// Computes `channelKey` for every channel that lacks one and whose radio has LoRa settings.
	static func backfillChannels(in context: ModelContext) throws -> Int {
		let pending = try context.fetch(FetchDescriptor<ChannelEntity>(predicate: #Predicate { $0.channelKey == nil }))
		var filled = 0
		for channel in pending {
			guard let myInfo = channel.myInfoChannel,
				  let lora = myInfo.myInfoNode?.loRaConfig else { continue }
			let primaryPSK = myInfo.channels.first { $0.index == 0 }?.psk
			channel.channelKey = channel.identityKey(primaryPSK: primaryPSK, usePreset: lora.usePreset, modemPreset: lora.modemPreset)
			filled += 1
		}
		return filled
	}

	/// The radio's channel keys by slot index, from its current channel and LoRa settings (a key
	/// changes when the user edits a channel's name or key, or the preset). With `updateStored`,
	/// stored `channelKey`s that differ are corrected; leave it off outside the ingest actor.
	static func channelKeysByIndex(for radioNum: Int64, in context: ModelContext, updateStored: Bool = true) throws -> [Int32: String] {
		let myInfos = try context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == radioNum }))
		guard let myInfo = myInfos.first, let lora = myInfo.myInfoNode?.loRaConfig else { return [:] }
		let primaryPSK = myInfo.channels.first { $0.index == 0 }?.psk
		var keys: [Int32: String] = [:]
		for channel in myInfo.channels {
			let key = channel.identityKey(primaryPSK: primaryPSK, usePreset: lora.usePreset, modemPreset: lora.modemPreset)
			if updateStored, channel.channelKey != key {
				channel.channelKey = key
			}
			keys[channel.index] = key
		}
		return keys
	}

	// MARK: - Messages

	/// Fills up to `limit` messages that have no `fromNum` yet. A message whose sender is gone
	/// gets `fromNum` 0 (the marker that it was visited) and no `messageKey`.
	static func backfillMessages(in context: ModelContext, ownRadio: Int64, channelKeys: [Int32: String], limit: Int) throws -> Int {
		var descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.fromNum == nil })
		descriptor.fetchLimit = limit
		let pending = try context.fetch(descriptor)
		for message in pending {
			let fromNum = message.fromUser?.num ?? 0
			message.fromNum = fromNum
			if let toNum = message.toUser?.num {
				message.toNum = toNum
			} else {
				message.toNum = broadcastNum
				if message.channelKey == nil {
					message.channelKey = channelKeys[message.channel]
				}
			}
			if message.localNodeNum == nil, ownRadio != 0 {
				message.localNodeNum = ownRadio
			}
			if message.messageKey == nil, fromNum != 0 {
				message.messageKey = MessageEntity.key(fromNum: fromNum, messageId: message.messageId)
			}
		}
		return pending.count
	}

	// MARK: - Observations

	/// Creates the store radio's observation of up to `limit` nodes that don't have one, copied
	/// from the node's fields (which, in a one-radio store, are that radio's view).
	///
	/// Once another radio has observations, the node's fields are that radio's view or the
	/// aggregate, and a copy would claim `ownRadio` heard nodes it never did, so nothing is
	/// created (T142). `MyInfoEntity` rows can't tell this: old stores may hold stray ones.
	static func backfillObservations(in context: ModelContext, ownRadio: Int64, limit: Int) throws -> Int {
		var others = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum != ownRadio })
		others.fetchLimit = 1
		guard try context.fetch(others).isEmpty else { return 0 }
		let existing = try context.fetch(FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum == ownRadio }))
		let observed = Set(existing.map(\.nodeNum))
		// Nodes are few (capped), so one sorted fetch of all of them is cheaper than paging with
		// a predicate SwiftData can't express (NOT IN a set).
		let nodes = try context.fetch(FetchDescriptor<NodeInfoEntity>(sortBy: [SortDescriptor(\.num)]))
		var filled = 0
		for node in nodes where node.num != ownRadio && !observed.contains(node.num) {
			guard filled < limit else { break }
			let observation = NodeObservationEntity(radioNum: ownRadio, nodeNum: node.num)
			observation.firstHeard = node.firstHeard
			observation.lastHeard = node.lastHeard
			observation.hopsAway = node.hopsAway
			observation.snr = node.snr
			observation.rssi = node.rssi
			observation.viaMqtt = node.viaMqtt
			observation.channel = node.channel
			observation.favorite = node.favorite
			observation.ignored = node.ignored
			observation.isKeyManuallyVerified = node.isKeyManuallyVerified
			observation.sessionPasskey = node.sessionPasskey
			observation.sessionExpiration = node.sessionExpiration
			context.insert(observation)
			filled += 1
		}
		return filled
	}
}
