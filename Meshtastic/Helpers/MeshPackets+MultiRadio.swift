//
//  MeshPackets+MultiRadio.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs
import OSLog
import SwiftData

// MARK: - The per-radio data model (feature 021)

extension MeshPackets {

	// MARK: - Channel keys

	/// Recomputes `radioNum`'s stored channel keys from its channels and LoRa settings, after
	/// either changes (T144). A real change of channel leaves a row in the radio's thread (T377),
	/// and the message lists are told to reload.
	///
	/// Saves this ingest first, then computes from what's saved in a throwaway context: this
	/// context is long-lived, and the main context replaces channel rows (staged refresh, QR
	/// import, the Channels editor) without this one seeing it, so computing here could write an
	/// old key back (T382).
	func refreshChannelKeys(radioNum: Int64) {
		guard !invalidated else { return }
		do {
			if modelContext.hasChanges {
				try modelContext.save()
			}
			let events = try MultiRadioBackfill.updateSavedChannelKeys(for: radioNum, container: modelContext.container)
			if events > 0 {
				Task { @MainActor in
					NotificationCenter.default.post(name: .meshMessagesDidChange, object: nil)
				}
			}
		} catch {
			Logger.data.error("💥 [MultiRadio] Channel keys failed: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Sent messages

	/// The message a routing or admin response answers. A request id is a packet id the radio
	/// sent, so the radio's own `messageKey` is tried first; rows without a key (not yet
	/// backfilled) fall back to the id alone. A packet id is only unique per sender, so matching
	/// the id alone could mark another node's message as delivered.
	func sentMessage(requestID: Int64, radioNum: Int64?) throws -> MessageEntity? {
		if let radioNum, radioNum != 0 {
			let key = MessageEntity.key(fromNum: radioNum, messageId: requestID)
			var keyed = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageKey == key })
			keyed.fetchLimit = 1
			if let match = try modelContext.fetch(keyed).first {
				return match
			}
		}
		// `messageKey == nil` is served by the same index.
		var unkeyed = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageKey == nil && $0.messageId == requestID })
		unkeyed.fetchLimit = 1
		return try modelContext.fetch(unkeyed).first
	}

	// MARK: - Receptions

	/// Records that `radioNum` received `packet`: signal, hops, relay (`PacketReceptionEntity`).
	/// Packets without an id or sender (locally generated ones) and copies the radio couldn't
	/// decrypt aren't recorded. Doesn't save; the debounced save at the end of
	/// `processFromRadio` does.
	func recordReception(packet: MeshPacket, radioNum: Int64) {
		guard packet.id != 0, packet.from != 0, radioNum != 0 else { return }
		guard case .decoded = packet.payloadVariant else { return }
		let key = PacketReceptionEntity.key(radioNum: radioNum, fromNum: Int64(packet.from), packetId: Int64(packet.id))
		do {
			var descriptor = FetchDescriptor<PacketReceptionEntity>(predicate: #Predicate { $0.key == key })
			descriptor.fetchLimit = 1
			let saved = try modelContext.fetch(descriptor).first
			let pending = modelContext.insertedModelsArray.lazy
				.compactMap { $0 as? PacketReceptionEntity }
				.first { $0.key == key }
			let reception = saved ?? pending ?? PacketReceptionEntity(radioNum: radioNum, fromNum: Int64(packet.from), packetId: Int64(packet.id))
			if saved == nil && pending == nil { modelContext.insert(reception) }
			reception.toNum = Int64(packet.to)
			reception.portNum = Int32(packet.decoded.portnum.rawValue)
			reception.channel = Int32(truncatingIfNeeded: packet.channel)
			reception.rxTime = packet.rxTime > 0 ? Date(timeIntervalSince1970: TimeInterval(packet.rxTime)) : Date()
			reception.snr = packet.rxSnr
			reception.rssi = packet.rxRssi
			reception.hopStart = Int32(truncatingIfNeeded: packet.hopStart)
			reception.hopLimit = Int32(truncatingIfNeeded: packet.hopLimit)
			reception.relayNode = Int64(packet.relayNode)
			reception.viaMqtt = packet.viaMqtt
		} catch {
			Logger.data.error("💥 [MultiRadio] Reception failed: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Observations

	/// `radioNum`'s observation of `node`, saved or still unsaved, created if missing. A new one
	/// starts from the node's own fields: with one radio they're that radio's view. By key: the
	/// `nodeNum` column has no index (T140).
	func observation(of node: NodeInfoEntity, by radioNum: Int64) throws -> NodeObservationEntity {
		let key = NodeObservationEntity.key(radioNum: radioNum, nodeNum: node.num)
		var descriptor = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.key == key })
		descriptor.fetchLimit = 1
		if let saved = try modelContext.fetch(descriptor).first {
			return saved
		}
		if let pending = modelContext.insertedModelsArray.lazy.compactMap({ $0 as? NodeObservationEntity }).first(where: { $0.key == key }) {
			return pending
		}
		let observation = NodeObservationEntity(radioNum: radioNum, nodeNum: node.num)
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
		modelContext.insert(observation)
		return observation
	}

	/// Deletes every observation of `nodeNums`, with the nodes themselves (T146). Observations
	/// only hold the node number, so nothing cascades. Doesn't save.
	func deleteObservations(ofNodes nodeNums: [Int64]) {
		NodeObservationEntity.delete(ofNodes: nodeNums, in: modelContext)
	}

	/// Mirrors the radio's node-DB entry into its observation, after `nodeInfoPacket` has written
	/// the node directly as before.
	func recordNodeDBObservation(_ nodeInfo: NodeInfo, node: NodeInfoEntity, radioNum: Int64?, reportsHeardOnCurrentLora: Bool = false) {
		guard let radioNum, radioNum != 0, node.num != radioNum else { return }
		do {
			let observation = try observation(of: node, by: radioNum)
			if nodeInfo.lastHeard > 0 {
				let candidate = Date(timeIntervalSince1970: TimeInterval(nodeInfo.lastHeard))
				if observation.lastHeard.map({ candidate > $0 }) ?? true {
					observation.lastHeard = candidate
				}
			}
			observation.snr = nodeInfo.snr
			observation.channel = Int32(truncatingIfNeeded: nodeInfo.channel)
			observation.hopsAway = Int32(truncatingIfNeeded: nodeInfo.hopsAway)
			observation.viaMqtt = nodeInfo.viaMqtt
			observation.favorite = nodeInfo.isFavorite
			observation.ignored = nodeInfo.isIgnored
			observation.isKeyManuallyVerified = nodeInfo.isKeyManuallyVerified
			// Nil unless the radio sends the field, as on the node (`MeshPackets.heardOnCurrentLora`).
			observation.heardOnCurrentLora = reportsHeardOnCurrentLora ? nodeInfo.heardOnCurrentLora : nil
		} catch {
			Logger.data.error("💥 [MultiRadio] Node-DB observation failed: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Background maintenance

	/// The radio a store's older rows belong to, for the backfill. A store holds one radio's data:
	/// the connected radio's when it has its record (`MyInfoEntity`), else the only radio it has a
	/// record of, else `preferred` when it has one. Not simply the preferred radio: a switch sets
	/// that before it clears the store, so an app ended mid-switch leaves the old radio's rows
	/// under the new radio's number. 0 when it can't tell, and the backfill then credits nothing.
	func storeRadio(connected: Int64?, preferred: Int64) -> Int64 {
		let radios = Set(((try? modelContext.fetch(FetchDescriptor<MyInfoEntity>())) ?? []).map(\.myNodeNum).filter { $0 != 0 })
		if let connected, radios.contains(connected) { return connected }
		if radios.count == 1, let only = radios.first { return only }
		return radios.contains(preferred) ? preferred : 0
	}

	/// Runs the backfill and reception pruning in committed chunks until both are done, the
	/// budget is spent, or the app comes back to the foreground. Part of the background
	/// maintenance pass, for the same reason as the eviction: writes to many rows can't race a
	/// view rendering them there, and it can stop at any chunk and resume on the next pass.
	///
	/// `ownRadio` is the radio the store holds data for (0 when none has connected yet).
	func runMultiRadioMaintenance(ownRadio: Int64, budget: Duration = .seconds(3)) async {
		let deadline = ContinuousClock.now + budget
		func shouldContinue() -> Bool {
			!invalidated && !Self.appIsActive && !Self.backgroundTimeExpired && ContinuousClock.now < deadline
		}

		var backfilled = 0
		while shouldContinue() {
			do {
				// Pending ingest (debounced position and telemetry saves) first, so the chunk reads
				// channel keys as saved rather than this context's copies.
				savePendingChanges(caller: "runMultiRadioMaintenance")
				let result = try MultiRadioBackfill.runChunk(in: modelContext, ownRadio: ownRadio)
				backfilled += result.total
				guard result.total > 0 else { break }
			} catch {
				modelContext.rollback()
				Logger.data.error("💥 [MultiRadio] Backfill chunk failed: \(error.localizedDescription, privacy: .public)")
				return
			}
			await Task.yield()
		}

		var pruned = 0
		while shouldContinue() {
			do {
				let removed = try PacketReceptionEntity.prune(in: modelContext)
				guard removed > 0 else { break }
				try modelContext.save()
				pruned += removed
			} catch {
				modelContext.rollback()
				Logger.data.error("💥 [MultiRadio] Reception prune failed: \(error.localizedDescription, privacy: .public)")
				return
			}
			await Task.yield()
		}

		if backfilled > 0 || pruned > 0 {
			Logger.data.info("🗄️ [MultiRadio] Backfilled \(backfilled) rows, pruned \(pruned) receptions")
		}
	}

	/// Runs the backfill to the end, a chunk at a time, letting other work on the actor through
	/// between chunks. After a restore, whose rows can be from an older build. Returns how many
	/// rows it filled.
	@discardableResult
	func drainMultiRadioBackfill(ownRadio: Int64) async throws -> Int {
		var total = 0
		while !invalidated {
			savePendingChanges(caller: "drainMultiRadioBackfill")
			let filled = try MultiRadioBackfill.runChunk(in: modelContext, ownRadio: ownRadio).total
			guard filled > 0 else { break }
			total += filled
			await Task.yield()
		}
		return total
	}
}

extension NodeObservationEntity {
	/// Deletes every observation of `nodeNums` in `context`. Doesn't save.
	static func delete(ofNodes nodeNums: [Int64], in context: ModelContext) {
		guard !nodeNums.isEmpty else { return }
		let descriptor = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { nodeNums.contains($0.nodeNum) })
		do {
			for observation in try context.fetch(descriptor) {
				context.delete(observation)
			}
		} catch {
			Logger.data.error("💥 [MultiRadio] Observation delete failed: \(error.localizedDescription, privacy: .public)")
		}
	}
}
