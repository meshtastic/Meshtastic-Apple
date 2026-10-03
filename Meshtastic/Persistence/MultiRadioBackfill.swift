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
/// It also converts channel keys stored in the `c1` format, which had no mesh, on channels and
/// messages (T379).
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
		/// Messages whose `c1` channel key was converted to the current format (T379).
		var rekeyed = 0
		/// Change rows removed because the row before them already ended on their channel.
		var duplicateEvents = 0

		var total: Int { channels + messages + observations + rekeyed + duplicateEvents }
	}

	/// Runs one chunk of each step and saves. Returns what it filled; zero means done.
	///
	/// `othersObserved` is whether another radio had observations when a multi-chunk drain began
	/// (T220): the drain lets packets through between chunks, and a joining radio's first packet
	/// would otherwise stop the observations for the rest of the nodes. Nil checks now.
	@discardableResult
	static func runChunk(in context: ModelContext, ownRadio: Int64, chunkSize: Int = 500, othersObserved: Bool? = nil) throws -> ChunkResult {
		var result = ChunkResult()
		result.channels = try backfillChannels(in: context)
		let channelKeys = try ownRadio == 0 ? [:] : channelKeysByIndex(for: ownRadio, in: context)
		result.messages = try backfillMessages(in: context, ownRadio: ownRadio, channelKeys: channelKeys, limit: chunkSize)
		result.rekeyed = try rekeyLegacyMessages(in: context, limit: chunkSize)
		result.duplicateEvents = try removeDuplicateChangeRows(in: context)
		if ownRadio != 0 {
			result.observations = try backfillObservations(in: context, ownRadio: ownRadio, limit: chunkSize, othersObserved: othersObserved)
		}
		if context.hasChanges {
			try context.save()
		}
		return result
	}

	// MARK: - Channels

	/// Computes `channelKey` for every channel that lacks one, or still has a `c1` key, and whose
	/// radio has LoRa settings. Neither is a change of channel, so neither leaves a change row.
	static func backfillChannels(in context: ModelContext) throws -> Int {
		// Channels are few, so the `c1` test runs in Swift rather than as a string predicate.
		let pending = try context.fetch(FetchDescriptor<ChannelEntity>()).filter { channel in
			channel.channelKey.map(ChannelIdentity.isLegacy) ?? true
		}
		var filled = 0
		for channel in pending {
			guard let myInfo = channel.myInfoChannel,
				  let lora = myInfo.myInfoNode?.loRaConfig else { continue }
			let primaryPSK = myInfo.channels.first { $0.index == 0 }?.psk
			channel.channelKey = channel.identityKey(
				primaryPSK: primaryPSK, usePreset: lora.usePreset, modemPreset: lora.modemPreset, network: MeshNetwork(radio: myInfo)
			)
			filled += 1
		}
		return filled
	}

	/// The radio's channel keys by slot index, from its current channel and LoRa settings (a key
	/// changes when the user edits a channel's name or key, the preset, or the mesh). With
	/// `updateStored`, stored `channelKey`s that differ are corrected, and a real change leaves a
	/// change row in the radio's thread for the slot (`updateChannelKeys`).
	static func channelKeysByIndex(for radioNum: Int64, in context: ModelContext, updateStored: Bool = true) throws -> [Int32: String] {
		try updateChannelKeys(for: radioNum, in: context, updateStored: updateStored).keys
	}

	/// `channelKeysByIndex`, also returning how many change rows it wrote, changed or removed
	/// (T377), so the caller can tell the message lists to reload. A stored key that was missing
	/// or in the `c1` format is filled in quietly: that isn't a change of channel. Doesn't save.
	///
	/// While the radio is paused (Local Mesh Discovery stepping presets), the keys are computed
	/// but the stored ones are kept (V22-2): the slot's conversation stays on the channel it had
	/// before the scan. A completed scan puts the radio back, so the first refresh after it finds
	/// nothing changed. An interrupted one leaves the radio on a scan preset, and that refresh
	/// records the change from the channel before the scan, so no stretch of history is lost.
	@discardableResult
	static func updateChannelKeys(for radioNum: Int64, in context: ModelContext, updateStored: Bool = true, now: Date = Date()) throws -> (keys: [Int32: String], events: Int) {
		let myInfos = try context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == radioNum }))
		guard let myInfo = myInfos.first, let lora = myInfo.myInfoNode?.loRaConfig else { return ([:], 0) }
		let primaryPSK = myInfo.channels.first { $0.index == 0 }?.psk
		let network = MeshNetwork(radio: myInfo)
		let store = updateStored && !ChannelChangeEvents.isPaused(radio: radioNum)
		var keys: [Int32: String] = [:]
		var events = 0
		for channel in myInfo.channels {
			let key = channel.identityKey(primaryPSK: primaryPSK, usePreset: lora.usePreset, modemPreset: lora.modemPreset, network: network)
			if store, channel.channelKey != key {
				if let previous = channel.channelKey, !ChannelIdentity.isLegacy(previous) {
					events += try ChannelChangeEvents.record(radio: radioNum, slot: channel.index, from: previous, to: key, in: context, now: now)
				}
				channel.channelKey = key
			}
			keys[channel.index] = key
		}
		return (keys, events)
	}

	// MARK: - Fresh reads

	// The main context is long-lived and doesn't take in what other contexts save: a channel or
	// LoRa object it loaded before the packet actor stored a preset change keeps the old values.
	// Keys read or computed there can be the channel before the change, so the conversation
	// shows the wrong channel's messages, "Via" offers radios on the old mesh, and a refresh
	// committed there writes the old key back and records the change twice. These read and
	// write in a throwaway context, which loads from the store (see AccessoryManager+FromRadio).

	/// `radioNum`'s stored channel keys by slot, as saved.
	static func storedChannelKeys(for radioNum: Int64, container: ModelContainer) -> [Int32: String] {
		let context = ModelContext(container)
		let myInfos = (try? context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == radioNum }))) ?? []
		var keys: [Int32: String] = [:]
		for channel in myInfos.first?.channels ?? [] {
			if let key = channel.channelKey { keys[channel.index] = key }
		}
		return keys
	}

	/// `radioNum`'s channel keys computed from its saved channels and LoRa settings.
	static func computedChannelKeys(for radioNum: Int64, container: ModelContainer) -> [Int32: String] {
		(try? channelKeysByIndex(for: radioNum, in: ModelContext(container), updateStored: false)) ?? [:]
	}

	/// `updateChannelKeys` from what's saved, then saved. Returns the change rows it wrote.
	@discardableResult
	static func updateSavedChannelKeys(for radioNum: Int64, container: ModelContainer, now: Date = Date()) throws -> Int {
		let context = ModelContext(container)
		let events = try updateChannelKeys(for: radioNum, in: context, now: now).events
		if context.hasChanges {
			try context.save()
		}
		return events
	}

	// MARK: - Legacy keys (T379)

	/// Converts up to `limit` messages still keyed in the `c1` format, which had no mesh. Each goes
	/// to the current key of the channel that has its `c1` key now: on the radio that stored it if
	/// that radio still has the channel, otherwise on the first radio that does. A channel no radio
	/// has any more keeps its rows together under an unknown mesh.
	///
	/// A string-prefix predicate can't be translated to SQL (the fetch throws an Objective-C
	/// exception and aborts the app), so the fetch only filters out rows without a key and sorts
	/// by key instead. Every key starts with its version, and `c1:` sorts before `c2:`, so any
	/// `c1` rows left come first; the prefix itself is checked in Swift.
	static func rekeyLegacyMessages(in context: ModelContext, limit: Int) throws -> Int {
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate { $0.channelKey != nil },
			sortBy: [SortDescriptor(\.channelKey)]
		)
		descriptor.fetchLimit = limit
		let pending = try context.fetch(descriptor).prefix { message in
			message.channelKey.map(ChannelIdentity.isLegacy) ?? false
		}
		guard !pending.isEmpty else { return 0 }
		let maps = try legacyKeyMaps(in: context)
		let radios = maps.keys.sorted()
		for message in pending {
			guard let legacy = message.channelKey else { continue }
			if let local = message.localNodeNum, let current = maps[local]?[legacy] {
				message.channelKey = current
			} else if let current = radios.lazy.compactMap({ maps[$0]?[legacy] }).first {
				message.channelKey = current
			} else {
				message.channelKey = ChannelIdentity.keyWithUnknownMesh(fromLegacy: legacy)
			}
		}
		return pending.count
	}

	/// For each radio with LoRa settings, its channels' `c1` keys mapped to their current keys.
	static func legacyKeyMaps(in context: ModelContext) throws -> [Int64: [String: String]] {
		var maps: [Int64: [String: String]] = [:]
		for myInfo in try context.fetch(FetchDescriptor<MyInfoEntity>()) {
			guard let lora = myInfo.myInfoNode?.loRaConfig else { continue }
			let primaryPSK = myInfo.channels.first { $0.index == 0 }?.psk
			let network = MeshNetwork(radio: myInfo)
			var map: [String: String] = [:]
			for channel in myInfo.channels.sorted(by: { $0.index < $1.index }) {
				let legacy = channel.legacyIdentityKey(primaryPSK: primaryPSK, usePreset: lora.usePreset, modemPreset: lora.modemPreset)
				if map[legacy] == nil {
					map[legacy] = channel.identityKey(primaryPSK: primaryPSK, usePreset: lora.usePreset, modemPreset: lora.modemPreset, network: network)
				}
			}
			maps[myInfo.myNodeNum] = map
		}
		return maps
	}

	// MARK: - Duplicate change rows

	/// Removes change rows whose radio's previous row for the slot already ended on the same
	/// channel: the same change recorded twice, from a context that still had the key from before
	/// it (fixed in `ChannelChangeEvents.record`; this cleans up stores that have them).
	static func removeDuplicateChangeRows(in context: ModelContext) throws -> Int {
		let eventRaw = MessageEntity.SystemEvent.channelChanged.rawValue
		// Change rows are few.
		let rows = try context.fetch(FetchDescriptor<MessageEntity>(
			predicate: #Predicate { $0.systemEvent == eventRaw },
			sortBy: [SortDescriptor(\.messageTimestamp), SortDescriptor(\.messageId)]
		))
		var lastKey: [String: String] = [:]
		var removed = 0
		for row in rows {
			let slot = "\(row.localNodeNum ?? 0):\(row.channel)"
			if let key = row.channelKey, lastKey[slot] == key {
				context.delete(row)
				removed += 1
				continue
			}
			lastKey[slot] = row.channelKey
		}
		return removed
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

	/// Whether any radio other than `ownRadio` has an observation.
	static func otherRadiosHaveObservations(than ownRadio: Int64, in context: ModelContext) throws -> Bool {
		var others = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum != ownRadio })
		others.fetchLimit = 1
		return try !context.fetch(others).isEmpty
	}

	/// Creates the store radio's observation of up to `limit` nodes that don't have one, copied
	/// from the node's fields (which, in a one-radio store, are that radio's view).
	///
	/// Once another radio has observations, the node's fields are that radio's view or the
	/// aggregate, and a copy would claim `ownRadio` heard nodes it never did, so nothing is
	/// created (T142). `MyInfoEntity` rows can't tell this: old stores may hold stray ones.
	static func backfillObservations(in context: ModelContext, ownRadio: Int64, limit: Int, othersObserved: Bool? = nil) throws -> Int {
		guard !(try othersObserved ?? otherRadiosHaveObservations(than: ownRadio, in: context)) else { return 0 }
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
