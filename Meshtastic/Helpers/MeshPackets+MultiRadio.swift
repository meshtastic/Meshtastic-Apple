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

// MARK: - Multi-radio maintenance (feature 021)

/// What `recordReception` found out about a packet.
enum ReceptionOutcome: Equatable {
	/// No id or sender to track it by (locally generated packets).
	case untracked
	/// No local radio has delivered this packet before.
	case first
	/// This radio delivered it before (a reconnect replay, store and forward). Handled exactly as
	/// before feature 021, so one radio behaves the same as it always did.
	case repeatFromSameRadio
	/// Another local radio already delivered it, and its handlers already ran.
	case heardByAnotherRadio
}

extension MeshPackets {

	// MARK: - The user's radios

	/// Node numbers of every radio the user has connected (one `MyInfoEntity` each). A packet
	/// from any of them is the user's own, whichever radio delivered it (T047).
	func localRadioNums() -> Set<Int64> {
		let myInfos = (try? modelContext.fetch(FetchDescriptor<MyInfoEntity>())) ?? []
		return Set(myInfos.map(\.myNodeNum).filter { $0 != 0 })
	}

	// MARK: - Receptions

	/// Records that `radioNum` received `packet` and reports whether any local radio had it
	/// already. Doesn't save; the caller's debounced save does.
	func recordReception(packet: MeshPacket, radioNum: Int64) -> ReceptionOutcome {
		guard packet.id != 0, packet.from != 0, radioNum != 0 else { return .untracked }
		let fromNum = Int64(packet.from)
		let packetId = Int64(packet.id)
		let known: [PacketReceptionEntity]
		do {
			known = try receptions(fromNum: fromNum, packetId: packetId)
		} catch {
			Logger.data.error("💥 [MultiRadio] Reception lookup failed: \(error.localizedDescription, privacy: .public)")
			return .untracked
		}

		let mine = known.first { $0.radioNum == radioNum }
		let reception = mine ?? PacketReceptionEntity(radioNum: radioNum, fromNum: fromNum, packetId: packetId)
		if mine == nil { modelContext.insert(reception) }
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

		if mine != nil { return .repeatFromSameRadio }
		return known.isEmpty ? .first : .heardByAnotherRadio
	}

	/// Saved and still-unsaved receptions of one packet (`fetch` only sees saved rows).
	func receptions(fromNum: Int64, packetId: Int64) throws -> [PacketReceptionEntity] {
		var found = try modelContext.fetch(FetchDescriptor<PacketReceptionEntity>(
			predicate: #Predicate { $0.fromNum == fromNum && $0.packetId == packetId }
		))
		let pending = modelContext.insertedModelsArray.lazy
			.compactMap { $0 as? PacketReceptionEntity }
			.filter { $0.fromNum == fromNum && $0.packetId == packetId }
		for reception in pending where !found.contains(where: { $0 === reception }) {
			found.append(reception)
		}
		return found
	}

	// MARK: - Observations

	/// Saved and still-unsaved observations of one node, by every local radio.
	func observations(ofNode nodeNum: Int64) throws -> [NodeObservationEntity] {
		var found = try modelContext.fetch(FetchDescriptor<NodeObservationEntity>(
			predicate: #Predicate { $0.nodeNum == nodeNum }
		))
		let pending = modelContext.insertedModelsArray.lazy
			.compactMap { $0 as? NodeObservationEntity }
			.filter { $0.nodeNum == nodeNum }
		for observation in pending where !found.contains(where: { $0 === observation }) {
			found.append(observation)
		}
		return found
	}

	/// The radio's observation of `node`, created if missing. The first observation of a node
	/// starts from the node's own fields: until now they were the one connected radio's view.
	func observation(of node: NodeInfoEntity, by radioNum: Int64, among existing: [NodeObservationEntity]) -> NodeObservationEntity {
		if let found = existing.first(where: { $0.radioNum == radioNum }) {
			return found
		}
		let observation = NodeObservationEntity(radioNum: radioNum, nodeNum: node.num)
		if existing.isEmpty {
			observation.firstHeard = node.firstHeard
			observation.lastHeard = node.lastHeard
			observation.hopsAway = node.hopsAway
			observation.snr = node.snr
			observation.rssi = node.rssi
			observation.viaMqtt = node.viaMqtt
			observation.channel = node.channel
		} else {
			observation.firstHeard = Date()
		}
		observation.favorite = node.favorite
		observation.ignored = node.ignored
		observation.isKeyManuallyVerified = node.isKeyManuallyVerified
		modelContext.insert(observation)
		return observation
	}
	/// Mirrors a radio's node-DB entry into that radio's observation, after `nodeInfoPacket` has
	/// written the node directly. With other radios observing the node too, the node then takes
	/// their aggregate instead.
	func recordNodeDBObservation(_ nodeInfo: NodeInfo, node: NodeInfoEntity, radioNum: Int64?) {
		guard let radioNum, radioNum != 0, node.num != radioNum else { return }
		do {
			let existing = try observations(ofNode: node.num)
			let observation = observation(of: node, by: radioNum, among: existing)
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
			let all = existing.contains { $0 === observation } ? existing : existing + [observation]
			if all.count > 1 {
				NodeObservationEntity.applyAggregate(all, to: node)
			}
		} catch {
			Logger.data.error("💥 [MultiRadio] Node-DB observation failed: \(error.localizedDescription, privacy: .public)")
		}
	}
}

// MARK: - Aggregate

extension NodeObservationEntity {
	/// Writes the node's per-radio fields as the aggregate of every local radio's observation
	/// (report §13.3.2), so the node list and map keep reading `NodeInfoEntity` unchanged:
	/// - `lastHeard` is the latest and `firstHeard` the earliest of any radio;
	/// - hops, signal, MQTT and channel come from the best path: heard over RF rather than MQTT,
	///   then fewest hops, then most recently.
	/// With a single observation its values are copied as they are.
	static func applyAggregate(_ observations: [NodeObservationEntity], to node: NodeInfoEntity) {
		guard let best = observations.min(by: isBetterPath) else { return }
		if observations.count == 1 {
			node.firstHeard = best.firstHeard
			node.lastHeard = best.lastHeard
		} else {
			node.firstHeard = observations.compactMap(\.firstHeard).min() ?? node.firstHeard
			node.lastHeard = observations.compactMap(\.lastHeard).max() ?? node.lastHeard
		}
		node.hopsAway = best.hopsAway
		node.snr = best.snr
		node.rssi = best.rssi
		node.viaMqtt = best.viaMqtt
		node.channel = best.channel
	}

	private static func isBetterPath(_ lhs: NodeObservationEntity, _ rhs: NodeObservationEntity) -> Bool {
		if lhs.viaMqtt != rhs.viaMqtt { return !lhs.viaMqtt }
		if lhs.hopsAway != rhs.hopsAway { return lhs.hopsAway < rhs.hopsAway }
		return (lhs.lastHeard ?? .distantPast) > (rhs.lastHeard ?? .distantPast)
	}
}

extension MeshPackets {

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
}
