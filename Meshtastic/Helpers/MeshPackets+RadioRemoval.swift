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
	@discardableResult
	func removeRadioData(_ radioNum: Int64, _ removal: RadioDataRemoval) -> RadioDataRemovalResult {
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
			let network = myInfos.first { $0.myNodeNum == radioNum }.flatMap(MeshNetwork.init(radio:))
			let sharesNetwork = network != nil && myInfos.contains { other in
				others.contains(other.myNodeNum) && MeshNetwork(radio: other) == network
			}
			let ownRadios = Set(myInfos.map(\.myNodeNum)).union([radioNum])

			if deleteMessages {
				result.messages = try deleteMessagesOfRadio(radioNum, keepingChannelsOf: others)
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
			try reaggregate(Array(heardByRadio.intersection(heardByOthers)), from: otherObservations)
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
	private func deleteMessagesOfRadio(_ radioNum: Int64, keepingChannelsOf others: Set<Int64>) throws -> Int {
		// Keys from each radio's LoRa settings, and the keys stored on its channels: a radio only
		// a merged backup knows has no LoRa settings in the store, but its channels keep their
		// keys (T177).
		let myInfos = try modelContext.fetch(FetchDescriptor<MyInfoEntity>())
		func storedKeys(of radio: Int64) -> [Int32: String] {
			var keys: [Int32: String] = [:]
			for channel in myInfos.first(where: { $0.myNodeNum == radio })?.channels ?? [] {
				if let key = channel.channelKey { keys[channel.index] = key }
			}
			return keys
		}
		let ownKeys = storedKeys(of: radioNum).merging(
			try MultiRadioBackfill.channelKeysByIndex(for: radioNum, in: modelContext, updateStored: false)
		) { _, computed in computed }
		var sharedKeys: Set<String> = []
		for other in others {
			sharedKeys.formUnion(storedKeys(of: other).values)
			sharedKeys.formUnion(try MultiRadioBackfill.channelKeysByIndex(for: other, in: modelContext, updateStored: false).values)
		}
		let messages = try modelContext.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.localNodeNum == radioNum }))
		var deleted = 0
		for message in messages {
			let toNum = message.toNum ?? (message.toUser == nil ? MultiRadioBackfill.broadcastNum : 0)
			if toNum == MultiRadioBackfill.broadcastNum {
				// A row without a key is placed by its slot on this radio.
				if let key = message.channelKey ?? ownKeys[message.channel], sharedKeys.contains(key) {
					continue
				}
			}
			modelContext.delete(message)
			deleted += 1
		}
		return deleted
	}

	/// Rewrites the node fields of `nodeNums` from the observations left in `observations`.
	private func reaggregate(_ nodeNums: [Int64], from observations: [NodeObservationEntity]) throws {
		guard !nodeNums.isEmpty else { return }
		let byNode = Dictionary(grouping: observations, by: \.nodeNum)
		let nodes = try modelContext.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { nodeNums.contains($0.num) }))
		for node in nodes {
			guard let remaining = byNode[node.num], !remaining.isEmpty else { continue }
			if remaining.count == 1, let only = remaining.first {
				// One observation left, perhaps a merged backup's from months ago: it only takes over
				// the path when it's current next to what the node last showed, and never moves the
				// node's last heard back (T176).
				let current = node.lastHeard.map { shown in
					(only.lastHeard ?? .distantPast) >= shown.addingTimeInterval(-NodeObservationEntity.currentWindow)
				} ?? true
				guard current else { continue }
				node.hopsAway = only.hopsAway
				node.snr = only.snr
				node.rssi = only.rssi
				node.viaMqtt = only.viaMqtt
				if only.radioNum == PreferredRadio.nodeNum { node.channel = only.channel }
				continue
			}
			NodeObservationEntity.applyAggregate(remaining, to: node, focusedRadio: PreferredRadio.nodeNum)
		}
	}
}
