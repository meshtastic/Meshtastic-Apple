//
//  MeshPackets+RadioRemoval.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import OSLog
import SwiftData

// MARK: - Resetting or removing one of several radios (feature 021, D-18, T147)

/// What happens to one radio's data when the store holds other radios too.
enum RadioDataRemoval: Sendable, Equatable {
	/// After a NodeDB or factory reset of the radio: its node list is gone from the radio, so
	/// its per-radio records go, and its messages if the user chose so.
	case reset(preserveFavorites: Bool, deleteMessages: Bool)
	/// Remove This Radio: as a reset with messages deleted, and the radio itself is forgotten.
	case remove
}

/// What `removeRadioData` deleted.
struct RadioDataRemovalResult: Equatable, Sendable {
	var messages = 0
	var nodes = 0
	var observations = 0
	var receptions = 0
}

/// One of the user's radios whose data is in the store.
struct StoredRadio: Equatable, Sendable {
	let nodeNum: Int64
	let name: String
}

extension MeshPackets {

	/// The user's radios whose data is in the store: every radio connected with this version
	/// (`lastConnected`), and every radio with observations (a merged backup's). A store from an
	/// older version can hold stray `MyInfoEntity` rows of radios it never kept data for; those
	/// don't count, so a single-radio user stays a single-radio user.
	func storedRadios() -> [StoredRadio] {
		let myInfos = (try? modelContext.fetch(FetchDescriptor<MyInfoEntity>())) ?? []
		return myInfos.compactMap { myInfo in
			let num = myInfo.myNodeNum
			guard num != 0 else { return nil }
			if myInfo.lastConnected == nil {
				var observed = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum == num })
				observed.fetchLimit = 1
				guard ((try? modelContext.fetchCount(observed)) ?? 0) > 0 else { return nil }
			}
			let user = myInfo.myInfoNode?.user
			return StoredRadio(nodeNum: num, name: user?.longName ?? user?.shortName ?? myInfo.bleName ?? num.toHex())
		}
		.sorted { $0.nodeNum < $1.nodeNum }
	}

	/// Whether the store holds data of a radio other than `radioNum` that `storedRadios` doesn't
	/// count (review V27-3), so removing `radioNum` mustn't clear the store:
	/// - rows still waiting for the backfill whose radio is another (`backfillOwner`);
	/// - messages on another radio's number from a radio that hasn't connected since the update
	///   and has no observations (T230).
	/// A stray `MyInfoEntity` without data still doesn't count. A fetch that fails counts as data.
	func holdsUncountedData(ofRadiosOtherThan radioNum: Int64, backfillOwner: Int64) -> Bool {
		if backfillOwner != 0, backfillOwner != radioNum, hasPendingBackfill() {
			return true
		}
		do {
			let others = Set(try modelContext.fetch(FetchDescriptor<MyInfoEntity>()).map(\.myNodeNum)).subtracting([0, radioNum])
			for num in others {
				var owned = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.localNodeNum == num })
				owned.fetchLimit = 1
				if try modelContext.fetchCount(owned) > 0 {
					return true
				}
			}
			return false
		} catch {
			Logger.data.error("💥 [MultiRadio] Checking other radios' data before removing \(radioNum.toHex(), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
			return true
		}
	}

	/// Whether `radioNum` is the radio the store's rows from before feature 021 belong to
	/// (`backfillOwner`) and some still wait for the backfill (review V28-3). Before its first
	/// connect since the update it has no `lastConnected` and no observations, so `storedRadios`
	/// doesn't count it, but the store is its data: removing it clears the store, or its old rows
	/// would stay with no radio and go to the next radio to join. A ghost after Clear App Data has
	/// nothing pending, and a stray radio row isn't the owner.
	func ownsPendingBackfill(_ radioNum: Int64, backfillOwner: Int64) -> Bool {
		radioNum != 0 && backfillOwner == radioNum && hasPendingBackfill()
	}

	/// Removes radio `radioNum`'s data from a store that holds other radios too (D-18). The
	/// caller has already disconnected it; a store holding only this radio is cleared as before
	/// (`clearDatabase`) instead.
	/// - Its observations and receptions go.
	/// - Nodes stay when another of the user's radios is on its network (`MeshNetwork`). When it
	///   is on a network of its own, the nodes only it heard go, favorites kept for a reset that
	///   preserves them and for a removal.
	/// - With messages deleted (always for a removal): all its direct messages, and its channel
	///   messages on channels none of the other radios has. A channel another radio has keeps its
	///   whole history, including what only this radio heard.
	/// - A removal also deletes its `MyInfoEntity` and channels, so it is no longer one of the
	///   user's radios and isn't reconnected, and its own node unless another radio hears it.
	/// `preferredRadio` is the radio whose channel slots and observations come first for what
	/// stays (the preferred radio, already handed on when this one was it, review V13 R13-2).
	@discardableResult
	func removeRadioData(_ radioNum: Int64, _ removal: RadioDataRemoval, preferredRadio: Int64 = PreferredRadio.nodeNum) -> RadioDataRemovalResult {
		var result = RadioDataRemovalResult()
		let deleteMessages: Bool
		let keepFavorites: Bool
		switch removal {
		case let .reset(preserveFavorites, messages):
			deleteMessages = messages
			keepFavorites = preserveFavorites
		case .remove:
			deleteMessages = true
			keepFavorites = true
		}

		do {
			let others = Set(storedRadios().map(\.nodeNum)).subtracting([radioNum])
			let myInfos = try modelContext.fetch(FetchDescriptor<MyInfoEntity>())
			// Each radio's mesh as saved (review V25-1): this context's LoRa settings and primary
			// channel can predate a change the main context saved, and the mesh decides which
			// nodes go.
			if modelContext.hasChanges {
				try modelContext.save()
			}
			let networks = MultiRadioBackfill.savedNetworks(container: modelContext.container)
			let network = networks[radioNum]
			let sharesNetwork = network != nil && others.contains { networks[$0] == network }
			let ownRadios = Set(myInfos.map(\.myNodeNum)).union([radioNum])

			if deleteMessages {
				result.messages = try deleteMessagesOfRadio(radioNum, keepingChannelsOf: others, moveKept: removal == .remove, preferredRadio: preferredRadio)
				try modelContext.save()
			}

			let ownObservations = try modelContext.fetch(FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum == radioNum }))
			let heardByRadio = Set(ownObservations.map(\.nodeNum))
			let otherObservations = try modelContext.fetch(FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum != radioNum }))
			let heardByOthers = Set(otherObservations.map(\.nodeNum))

			if !sharesNetwork {
				let onlyThisRadio = Array(heardByRadio.subtracting(heardByOthers).subtracting(ownRadios))
				let nodes = try modelContext.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { onlyThisRadio.contains($0.num) }))
				for node in nodes where !(keepFavorites && node.favorite) {
					modelContext.delete(node)
					result.nodes += 1
				}
				try modelContext.save()
			}

			for observation in ownObservations {
				modelContext.delete(observation)
			}
			result.observations = ownObservations.count
			try modelContext.save()

			let receptions = try modelContext.fetch(FetchDescriptor<PacketReceptionEntity>(predicate: #Predicate { $0.radioNum == radioNum }))
			for reception in receptions {
				modelContext.delete(reception)
			}
			result.receptions = receptions.count
			try modelContext.save()

			if removal == .remove {
				for myInfo in myInfos where myInfo.myNodeNum == radioNum {
					modelContext.delete(myInfo)
				}
				try modelContext.save()
				if !heardByOthers.contains(radioNum) {
					var own = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == radioNum })
					own.fetchLimit = 1
					if let node = try modelContext.fetch(own).first {
						modelContext.delete(node)
						try modelContext.save()
					}
				}
			}

			// The nodes this radio heard that stay now show the other radios' view.
			try reaggregate(Array(heardByRadio.intersection(heardByOthers)), from: otherObservations, preferredRadio: preferredRadio)
			try modelContext.save()
			lookupRadiosReadAt = .distantPast
			Logger.data.info("🗑️ [MultiRadio] Removed radio \(radioNum.toHex(), privacy: .public)'s data (\(String(describing: removal), privacy: .public)): \(result.messages) messages, \(result.nodes) nodes, \(result.observations) observations, \(result.receptions) receptions; shares a network: \(sharesNetwork)")
		} catch {
			modelContext.rollback()
			Logger.data.error("💥 [MultiRadio] Removing radio \(radioNum.toHex(), privacy: .public)'s data failed: \(error.localizedDescription, privacy: .public)")
		}
		return result
	}

	/// Deletes `radioNum`'s direct messages, and its channel messages whose channel none of
	/// `others` has. Returns how many went. Doesn't save.
	///
	/// With `moveKept` (a removal), each kept channel message is moved onto a remaining radio that
	/// has its channel: that radio, its slot for the channel, and the key if the row had none
	/// (T222). Left on a radio that's gone, it would show in whatever channel has its slot number
	/// once one radio is left, or in no channel at all.
	private func deleteMessagesOfRadio(_ radioNum: Int64, keepingChannelsOf others: Set<Int64>, moveKept: Bool = false, preferredRadio: Int64) throws -> Int {
		// Keys from each radio's LoRa settings, and the keys stored on its channels: a radio only
		// a merged backup knows has no LoRa settings in the store, but its channels keep their
		// keys (T177). Both as saved (review V25-1): this context's channels can predate a
		// rename, key change or QR import the main context saved, and these decide which
		// messages stay and where they move.
		let container = modelContext.container
		func radioKeys(of radio: Int64) -> [Int32: String] {
			MultiRadioBackfill.storedChannelKeys(for: radio, container: container).merging(
				MultiRadioBackfill.computedChannelKeys(for: radio, container: container)
			) { _, computed in computed }
		}
		let ownKeys = radioKeys(of: radioNum)
		var sharedKeys: Set<String> = []
		// Where each shared channel lives on the remaining radios: the preferred radio's slot
		// first, then the lowest radio number's.
		var slotForKey: [String: (radio: Int64, index: Int32)] = [:]
		let preferred = preferredRadio
		for other in others.sorted(by: { ($0 == preferred ? 0 : 1, $0) < ($1 == preferred ? 0 : 1, $1) }) {
			let keys = radioKeys(of: other)
			for (index, key) in keys.sorted(by: { $0.key < $1.key }) where slotForKey[key] == nil {
				slotForKey[key] = (other, index)
			}
			sharedKeys.formUnion(keys.values)
		}
		let messages = try modelContext.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.localNodeNum == radioNum }))
		var deleted = 0
		for message in messages {
			// A channel-change row tells the history of this radio's slot, so it goes with it.
			if message.isSystemEvent {
				modelContext.delete(message)
				deleted += 1
				continue
			}
			let toNum = message.toNum ?? (message.toUser == nil ? MultiRadioBackfill.broadcastNum : 0)
			if toNum == MultiRadioBackfill.broadcastNum {
				// A row without a key is placed by its slot on this radio.
				if let key = message.channelKey ?? ownKeys[message.channel], sharedKeys.contains(key) {
					if moveKept, let slot = slotForKey[key] {
						message.localNodeNum = slot.radio
						message.channel = slot.index
						message.channelKey = key
					}
					continue
				}
			}
			modelContext.delete(message)
			deleted += 1
		}
		return deleted
	}

	/// Rewrites the node fields of `nodeNums` from the observations left in `observations`.
	private func reaggregate(_ nodeNums: [Int64], from observations: [NodeObservationEntity], preferredRadio: Int64) throws {
		guard !nodeNums.isEmpty else { return }
		let byNode = Dictionary(grouping: observations, by: \.nodeNum)
		let nodes = try modelContext.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { nodeNums.contains($0.num) }))
		for node in nodes {
			guard let remaining = byNode[node.num], !remaining.isEmpty else { continue }
			// What's left may be merged backups' observations from months ago: they only take over
			// the path when they're current next to what the node last showed, and never move the
			// node's last heard back (T176 for one left, T195 for several).
			let shown = node.lastHeard
			let newest = remaining.compactMap(\.lastHeard).max() ?? .distantPast
			if let shown, newest < shown.addingTimeInterval(-NodeObservationEntity.currentWindow) { continue }
			if remaining.count > 1 {
				let firstHeard = node.firstHeard
				NodeObservationEntity.applyAggregate(remaining, to: node, firstRadio: preferredRadio)
				if let shown, (node.lastHeard ?? .distantPast) < shown { node.lastHeard = shown }
				if let firstHeard, (node.firstHeard ?? .distantFuture) > firstHeard { node.firstHeard = firstHeard }
				continue
			}
			if let only = remaining.first {
				node.hopsAway = only.hopsAway
				node.snr = only.snr
				node.rssi = only.rssi
				node.viaMqtt = only.viaMqtt
				if only.radioNum == preferredRadio { node.channel = only.channel }
			}
		}
	}
}
