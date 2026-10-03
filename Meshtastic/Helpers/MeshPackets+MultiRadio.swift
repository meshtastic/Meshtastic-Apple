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
	/// No id or sender to track it by (locally generated packets), or a copy this radio couldn't
	/// decrypt: its handlers don't run, so it mustn't stand in for another radio's decoded copy.
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

	/// The radios a keyed lookup tries, `first` (the radio at hand) leading: the user's radios,
	/// re-read at most every few seconds rather than on every packet. A radio added since is
	/// covered by `first`, which is the radio the packet came in on.
	func lookupRadios(first: Int64?) -> [Int64] {
		let now = Date()
		if now.timeIntervalSince(lookupRadiosReadAt) > 5 {
			let myInfos = (try? modelContext.fetch(FetchDescriptor<MyInfoEntity>())) ?? []
			cachedLookupRadios = Set(myInfos.map(\.myNodeNum).filter { $0 != 0 })
			cachedConnectedRadios = Set(myInfos.filter { $0.lastConnected != nil }.map(\.myNodeNum).filter { $0 != 0 })
			lookupRadiosReadAt = now
		}
		var radios: [Int64] = []
		if let first, first != 0 { radios.append(first) }
		radios.append(contentsOf: cachedLookupRadios.subtracting(radios).sorted())
		return radios
	}

	// MARK: - Channel keys

	/// Recomputes `radioNum`'s stored channel keys from its channels and LoRa settings, after
	/// either changes (T144). A channel without a key would show every radio's messages in its
	/// slot; a stale key another channel's. A real change of channel leaves a row in the radio's
	/// thread (T377), and the message lists are told to reload.
	///
	/// Saves this ingest first, then computes from what's saved in a throwaway context (review
	/// V24-2): this context is long-lived, and the main context replaces channel rows (staged
	/// refresh, QR import, the Channels editor) without this one seeing it, so computing here
	/// could write an old key back, as T382 found in the other direction.
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

	/// True when any of the user's radios has the channel `key` muted (T158). Mute is set on one
	/// radio's channel list, but the message may come in through another radio first.
	func isChannelMutedOnAnyRadio(key: String?) -> Bool {
		guard let key else { return false }
		let muted = FetchDescriptor<ChannelEntity>(predicate: #Predicate { $0.channelKey == key && $0.mute })
		return ((try? modelContext.fetchCount(muted)) ?? 0) > 0
	}

	// MARK: - Admin sessions

	/// Stores a remote-admin session passkey on the asking radio's observation of the node
	/// (T045). The node's own `sessionPasskey`, written by the config handlers, stays the
	/// first radio's until the send path reads per radio (T060).
	func recordAdminSession(passkey: Data, nodeNum: Int64, radioNum: Int64) {
		guard nodeNum != radioNum else { return }
		var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		descriptor.fetchLimit = 1
		do {
			guard let node = try modelContext.fetch(descriptor).first else { return }
			let observation = observation(of: node, by: radioNum, among: try observations(ofNode: nodeNum, radioNum: radioNum))
			observation.sessionPasskey = passkey
			observation.sessionExpiration = Date().addingTimeInterval(300)
		} catch {
			Logger.data.error("💥 [MultiRadio] Admin session failed: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Notifications (T091)

	/// Unread direct messages addressed to the user's radios other than `radioNum` (T090), by
	/// `toNum`, which every message received with more than one radio carries.
	func unreadDirectMessageCount(toRadiosOtherThan radioNum: Int64?) -> Int {
		var total = 0
		for otherRadio in localRadioNums() where otherRadio != radioNum {
			let predicate: Predicate<MessageEntity> = #Predicate { message in
				message.toNum == otherRadio && message.read == false && message.isEmoji == false
			}
			total += (try? modelContext.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
		}
		return total
	}

	/// The short name of the radio `message` came in on, when the store knows more than one of
	/// the user's radios; nil otherwise, so single-radio notifications don't change.
	func receivingRadioName(for message: MessageEntity) -> String? {
		guard let radioNum = message.localNodeNum,
			  ((try? modelContext.fetchCount(FetchDescriptor<MyInfoEntity>())) ?? 0) > 1 else { return nil }
		var descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == radioNum })
		descriptor.fetchLimit = 1
		let user = try? modelContext.fetch(descriptor).first
		return user?.shortName ?? user?.longName ?? radioNum.toHex()
	}

	// MARK: - Remembered radios

	/// Records a finished connection on the radio's `MyInfoEntity`: when, over what, and
	/// whether to bring it back automatically (`autoConnect`, nil leaves it as it is).
	func noteRadioConnected(nodeNum: Int64, transport: TransportType, autoConnect: Bool?) {
		var descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == nodeNum })
		descriptor.fetchLimit = 1
		guard let myInfo = try? modelContext.fetch(descriptor).first else { return }
		if myInfo.lastConnected == nil {
			// It now votes on favorite / ignored (`cachedConnectedRadios`), T184.
			lookupRadiosReadAt = .distantPast
		}
		myInfo.lastConnected = Date()
		myInfo.transport = transport.rawValue
		if let autoConnect {
			myInfo.autoConnect = autoConnect
		}
		savePendingChanges()
	}

	/// Remembers the radios on `peripheralIds` to come back alongside the first one: radios iOS
	/// restored that aren't the first radio's restore (T190). A radio only ever connected first isn't
	/// remembered otherwise, and the remembered-radio reconnect is what claims restored radios.
	func rememberRadios(peripheralIds: [String]) {
		guard !peripheralIds.isEmpty else { return }
		let myInfos = (try? modelContext.fetch(FetchDescriptor<MyInfoEntity>())) ?? []
		for myInfo in myInfos where myInfo.peripheralId.map(peripheralIds.contains) == true && !myInfo.autoConnect {
			myInfo.autoConnect = true
		}
		savePendingChanges()
	}

	/// The peripheral radio `nodeNum` last connected from, if the store knows it.
	func peripheralId(ofRadio nodeNum: Int64) -> String? {
		var descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == nodeNum })
		descriptor.fetchLimit = 1
		return (try? modelContext.fetch(descriptor))?.first?.peripheralId
	}

	/// The user's radios connected with this version (`lastConnected`), by node number: the ones
	/// a service can be given (W-15). A merged backup's radio isn't one until it connects.
	func radiosConnectedWithThisVersion() -> [StoredRadio] {
		storedRadios().filter { radio in
			let num = radio.nodeNum
			var descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == num })
			descriptor.fetchLimit = 1
			return (try? modelContext.fetch(descriptor))?.first?.lastConnected != nil
		}
	}

	/// Every radio in the store with the peripheral id it was last connected on.
	func radioPeripheralIds() -> [(String, Int64)] {
		((try? modelContext.fetch(FetchDescriptor<MyInfoEntity>())) ?? []).compactMap { myInfo in
			guard let peripheralId = myInfo.peripheralId, !peripheralId.isEmpty, myInfo.myNodeNum != 0 else { return nil }
			return (peripheralId, myInfo.myNodeNum)
		}
	}

	func setRadioAutoConnect(nodeNum: Int64, _ autoConnect: Bool) {
		var descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == nodeNum })
		descriptor.fetchLimit = 1
		guard let myInfo = try? modelContext.fetch(descriptor).first, myInfo.autoConnect != autoConnect else { return }
		myInfo.autoConnect = autoConnect
		savePendingChanges()
	}

	/// A radio to bring back alongside the first one.
	struct RememberedRadio: Sendable, Equatable {
		let nodeNum: Int64
		let peripheralId: String
		let name: String
		let transport: TransportType
	}

	/// Radios marked `autoConnect`, other than `excluding`.
	func rememberedRadios(excluding: Set<Int64>) -> [RememberedRadio] {
		let rows = (try? modelContext.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.autoConnect }))) ?? []
		return rows.compactMap { row in
			guard !excluding.contains(row.myNodeNum), let peripheralId = row.peripheralId, !peripheralId.isEmpty else { return nil }
			let transport = row.transport.flatMap(TransportType.init(rawValue:)) ?? .ble
			let name = row.myInfoNode?.user?.longName ?? row.bleName ?? row.myNodeNum.toHex()
			return RememberedRadio(nodeNum: row.myNodeNum, peripheralId: peripheralId, name: name, transport: transport)
		}
	}

	// MARK: - ACK matching

	/// The message a routing or admin response answers. A request id is a packet id the
	/// delivering radio sent, so that radio's `messageKey` is tried first; rows without a key
	/// (not yet backfilled, admin log entries) fall back to the id alone.
	func sentMessage(requestID: Int64, radioNum: Int64?) throws -> MessageEntity? {
		// Every message the user sends is keyed by the radio that sent it, the delivering radio
		// first. Lookups by key use its index; `messageId` has none (T140).
		for sender in lookupRadios(first: radioNum) {
			let key = MessageEntity.key(fromNum: sender, messageId: requestID)
			var keyed = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageKey == key })
			keyed.fetchLimit = 1
			if let match = try modelContext.fetch(keyed).first {
				return match
			}
		}
		// Rows the backfill hasn't keyed yet. `messageKey == nil` is served by the same index.
		var legacy = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageKey == nil && $0.messageId == requestID })
		legacy.fetchLimit = 1
		return try modelContext.fetch(legacy).first
	}

	// MARK: - Receptions

	/// Records that `radioNum` received `packet` and reports whether any local radio had it
	/// already. Doesn't save; the caller's debounced save does.
	func recordReception(packet: MeshPacket, radioNum: Int64) -> ReceptionOutcome {
		guard packet.id != 0, packet.from != 0, radioNum != 0 else { return .untracked }
		// A radio without the packet's channel still passes it on encrypted. Recording it would
		// mark the packet handled and drop the decoded copy another radio delivers (T141).
		guard case .decoded = packet.payloadVariant else { return .untracked }
		let fromNum = Int64(packet.from)
		let packetId = Int64(packet.id)
		let known: [PacketReceptionEntity]
		do {
			known = try receptions(fromNum: fromNum, packetId: packetId, radioNum: radioNum)
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

		saveIfRetiring()
		if mine != nil { return .repeatFromSameRadio }
		return known.isEmpty ? .first : .heardByAnotherRadio
	}

	/// Saved and still-unsaved receptions of one packet (`fetch` only sees saved rows).
	/// Looked up by key for each of the user's radios (`radioNum` first): a reception only ever
	/// comes from one of them, and the key is indexed where `fromNum` and `packetId` aren't, so
	/// this is a handful of index lookups per packet rather than a table scan (T140).
	func receptions(fromNum: Int64, packetId: Int64, radioNum: Int64? = nil) throws -> [PacketReceptionEntity] {
		var found: [PacketReceptionEntity] = []
		for radio in lookupRadios(first: radioNum) {
			let key = PacketReceptionEntity.key(radioNum: radio, fromNum: fromNum, packetId: packetId)
			var descriptor = FetchDescriptor<PacketReceptionEntity>(predicate: #Predicate { $0.key == key })
			descriptor.fetchLimit = 1
			found.append(contentsOf: try modelContext.fetch(descriptor))
		}
		let pending = modelContext.insertedModelsArray.lazy
			.compactMap { $0 as? PacketReceptionEntity }
			.filter { $0.fromNum == fromNum && $0.packetId == packetId }
		for reception in pending where !found.contains(where: { $0 === reception }) {
			found.append(reception)
		}
		return found
	}

	// MARK: - Observations

	/// True when several of the user's radios observe `nodeNum`: its hops and channel slot are then
	/// the aggregate's (`applyAggregate`), and a packet handler mustn't overwrite them with the
	/// radio that delivered this packet (T204). With one radio the handlers write them as before.
	func nodeFieldsAreAggregated(_ nodeNum: Int64) -> Bool {
		((try? observations(ofNode: nodeNum))?.count ?? 0) > 1
	}

	/// Saved and still-unsaved observations of one node, by every local radio (`radioNum` first).
	/// By key, like `receptions`: `nodeNum` has no index (T140).
	func observations(ofNode nodeNum: Int64, radioNum: Int64? = nil) throws -> [NodeObservationEntity] {
		var found: [NodeObservationEntity] = []
		for radio in lookupRadios(first: radioNum) {
			let key = NodeObservationEntity.key(radioNum: radio, nodeNum: nodeNum)
			var descriptor = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.key == key })
			descriptor.fetchLimit = 1
			found.append(contentsOf: try modelContext.fetch(descriptor))
		}
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
	/// Deletes every radio's observations of `nodeNums`, with the nodes themselves (T146).
	/// Observations only hold the node number, so nothing cascades; left behind, they would
	/// feed the aggregate and Heard By again when the node comes back. Doesn't save.
	func deleteObservations(ofNodes nodeNums: [Int64]) {
		NodeObservationEntity.delete(ofNodes: nodeNums, in: modelContext)
	}

	/// Mirrors a radio's node-DB entry into that radio's observation, after `nodeInfoPacket` has
	/// written the node directly. With other radios observing the node too, the node then takes
	/// their aggregate instead.
	func recordNodeDBObservation(_ nodeInfo: NodeInfo, node: NodeInfoEntity, radioNum: Int64?) {
		guard let radioNum, radioNum != 0, node.num != radioNum else { return }
		do {
			let existing = try observations(ofNode: node.num, radioNum: radioNum)
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
				NodeObservationEntity.applyAggregate(all, to: node, firstRadio: PreferredRadio.nodeNum)
				// FR-022: favorite, ignored and a verified key hold if any of the user's radios says
				// so, not whichever radio's node DB came last (T164). Radios only a merged backup
				// knows don't count; the radio this dump is from always does.
				_ = lookupRadios(first: radioNum)
				let voting = all.filter { $0.radioNum == radioNum || cachedConnectedRadios.contains($0.radioNum) }
				node.favorite = voting.contains { $0.favorite }
				node.ignored = voting.contains { $0.ignored }
				node.isKeyManuallyVerified = voting.contains { $0.isKeyManuallyVerified }
			}
		} catch {
			Logger.data.error("💥 [MultiRadio] Node-DB observation failed: \(error.localizedDescription, privacy: .public)")
		}
	}
}

// MARK: - Aggregate

extension NodeObservationEntity {
	/// Deletes every radio's observations of `nodeNums` in `context`. Doesn't save.
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

	/// How far behind the newest observation another can be and still count as current. Nodes
	/// send something at least every half hour by default, so a radio still in range of the
	/// node has heard it within the hour.
	static let currentWindow: TimeInterval = 60 * 60

	/// Writes the node's per-radio fields as the aggregate of every local radio's observation
	/// (report §13.3.2), so the node list and map keep reading `NodeInfoEntity` unchanged:
	/// - `lastHeard` is the latest and `firstHeard` the earliest of any radio;
	/// - hops, signal and MQTT come from the best current path: among observations heard within
	///   `currentWindow` of the newest, heard over RF rather than MQTT, then fewest hops, then
	///   most recently. An old observation (a radio that's away, a merged backup) doesn't count;
	/// - `channel` is a slot number on one radio, so it comes only from `firstRadio`'s own
	///   observation, the radio that sends to the node; without one it is left as it is (T143).
	/// With a single observation its values are copied as they are.
	static func applyAggregate(_ observations: [NodeObservationEntity], to node: NodeInfoEntity, firstRadio: Int64) {
		guard !observations.isEmpty else { return }
		if observations.count == 1, let only = observations.first {
			node.firstHeard = only.firstHeard
			node.lastHeard = only.lastHeard
			node.hopsAway = only.hopsAway
			node.snr = only.snr
			node.rssi = only.rssi
			node.viaMqtt = only.viaMqtt
			node.channel = only.channel
			return
		}
		node.firstHeard = observations.compactMap(\.firstHeard).min() ?? node.firstHeard
		node.lastHeard = observations.compactMap(\.lastHeard).max() ?? node.lastHeard
		guard let best = current(observations).min(by: isBetterPath) else { return }
		node.hopsAway = best.hopsAway
		node.snr = best.snr
		node.rssi = best.rssi
		node.viaMqtt = best.viaMqtt
		if let own = observations.first(where: { $0.radioNum == firstRadio }) {
			node.channel = own.channel
		}
	}

	/// The observations heard within `currentWindow` of the newest; all of them when none has
	/// been heard.
	static func current(_ observations: [NodeObservationEntity]) -> [NodeObservationEntity] {
		guard let newest = observations.compactMap(\.lastHeard).max() else { return observations }
		return observations.filter { observation in
			guard let heard = observation.lastHeard else { return false }
			return newest.timeIntervalSince(heard) <= currentWindow
		}
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
