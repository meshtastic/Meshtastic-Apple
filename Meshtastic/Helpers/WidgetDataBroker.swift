//
//  WidgetDataBroker.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  Builds WidgetSnapshots from the database and tells WidgetKit when to reload.
//  Runs only in the app process; the widget extension just reads the snapshot.
//
//  Reload budget: WidgetKit allows roughly 40-70 background reloads per widget
//  per day, so refreshes are debounced (a node DB dump is one write, not
//  hundreds) and each widget kind has a minimum reload interval. Widgets render
//  ages with relative dates, so nothing looks frozen between reloads.
//

import Combine
import Foundation
import OSLog
import SwiftData
import WidgetKit

@MainActor
final class WidgetDataBroker {
	static let shared = WidgetDataBroker()

	/// Widget kind identifiers. The widgets ship in later pull requests;
	/// reloading a kind nobody has added yet is a no-op.
	enum Kind: String, CaseIterable {
		case stats = "MeshLocalStats"
		case tracker = "MeshNodeTracker"
		case messages = "MeshMessages"
		case map = "MeshNodeMap"
	}

	enum Trigger: Hashable {
		case connection   // connect, disconnect, state changes
		case config       // config complete, DB dump saved, channel saves
		case messages     // ingest or mark-read (via .meshMessagesDidChange)
		case localStats   // 15-minute LocalStats telemetry
	}

	private var cancellables = Set<AnyCancellable>()
	private var pendingRefresh: Task<Void, Never>?
	/// The build in progress. Builds run one at a time so an older one can't finish last and
	/// overwrite a newer snapshot.
	private var buildInFlight: Task<Void, Never>?
	/// Triggers that arrived during the current debounce window. The reload plan
	/// is the union over all of them — keeping only the newest trigger dropped
	/// the earlier triggers' reload kinds.
	private var pendingTriggers: Set<Trigger> = []
	/// When the oldest pending trigger arrived, so a steady stream of triggers
	/// can't postpone the write past the ceiling.
	private var pendingSince: Date?
	private var lastReload: [Kind: Date] = [:]
	/// A map reload that was due while a map render was in flight.
	private var mapReloadDeferred = false
	/// LocalStats are keyed to the radio that produced them so a radio switch
	/// can't show the previous radio's counters as the new one's.
	private var latestLocalStats: LocalStatsSnapshot?
	private var latestLocalStatsNodeNum: Int64?
	/// Keeps DM-partner resolution working for the snapshot written right after
	/// a disconnect clears activeDeviceNum.
	private var lastKnownRadioNum: Int64?
	/// Connection flap damping: a reconnect storm fires updateState repeatedly,
	/// but only a change of (state, radio) earns the immediate reload plan — a
	/// radio switch that settles inside one debounce window must still reload.
	private var lastWrittenConnectionKey: String?
	/// Message-reload damping: immediate only when unread counts or the newest
	/// message actually changed, so a busy channel can't exhaust the budget.
	private var lastWrittenMessagesKey: String?

	private init() {}

	/// Called once at app launch. Message changes funnel through the existing
	/// .meshMessagesDidChange notification, which covers ingest and mark-read.
	func start() {
		NotificationCenter.default.publisher(for: .meshMessagesDidChange)
			.debounce(for: .seconds(2), scheduler: DispatchQueue.main)
			.sink { [weak self] _ in self?.refresh(.messages) }
			.store(in: &cancellables)
	}

	/// LocalStats arrive on the MeshPackets actor; it passes plain values here,
	/// along with the radio they belong to.
	func updateLocalStats(_ stats: LocalStatsSnapshot, nodeNum: Int64) {
		// The firmware replays buffered packets after the node DB dump (#2582);
		// never let a replayed, older LocalStats overwrite fresher counters.
		if nodeNum == latestLocalStatsNodeNum,
		   let current = latestLocalStats,
		   stats.statsAt < current.statsAt {
			return
		}
		latestLocalStats = stats
		latestLocalStatsNodeNum = nodeNum
		refresh(.localStats)
	}

	func refresh(_ trigger: Trigger) {
		pendingTriggers.insert(trigger)
		// Trailing debounce: coalesce the burst, then build once with every
		// trigger that arrived during the window. A 5 s ceiling (same as
		// MeshPackets.scheduleDebouncedSave) keeps a steady stream — a node DB
		// dump changes connection state per node — from postponing forever.
		let since = pendingSince ?? Date()
		pendingSince = since
		let delay = min(2.0, max(0, 5.0 - Date().timeIntervalSince(since)))
		pendingRefresh?.cancel()
		pendingRefresh = Task { @MainActor [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
			guard !Task.isCancelled, let self else { return }
			self.pendingSince = nil
			// Mid node database download, every node changes what the widgets show. Keep the
			// triggers and look again shortly; the download's save usually refreshes first, and
			// this still builds if that save fails.
			if AccessoryManager.shared.nodeDatabaseDumpInProgress {
				self.retry(after: 5)
				return
			}
			await self.buildInFlight?.value
			guard !Task.isCancelled else { return }
			let triggers = self.pendingTriggers
			self.pendingTriggers = []
			let build = Task { @MainActor in await self.buildAndStore(triggers) }
			self.buildInFlight = build
			await build.value
		}
	}

	/// Runs the debounce again for the triggers still pending, after `delay` seconds.
	private func retry(after delay: TimeInterval) {
		Task { @MainActor [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
			guard let self, let trigger = self.pendingTriggers.first else { return }
			self.refresh(trigger)
		}
	}

	// MARK: - Snapshot build

	private func buildAndStore(_ triggers: Set<Trigger>) async {
		// Before first unlock the store is provisional; skip and let the next
		// trigger rebuild. Class C file writes would fail here anyway.
		guard !PersistenceController.shared.isProvisionalPendingFirstUnlock else { return }

		let accessoryManager = AccessoryManager.shared
		let connectionState = Self.connectionState(for: accessoryManager)
		// Radio identity must survive disconnects and relaunches so channel
		// names, DM partners and the radio's own name stay right while offline:
		// live value, then this process's last connect, then the persisted
		// preferred peripheral the rest of the codebase falls back to.
		let liveRadioNum = accessoryManager.activeDeviceNum
		if let liveRadioNum { lastKnownRadioNum = liveRadioNum }
		let persistedNum = Int64(UserDefaults.preferredPeripheralNum)
		let radioNum = liveRadioNum ?? lastKnownRadioNum ?? (persistedNum > 0 ? persistedNum : nil)

		// Drop stats that belong to a different radio than the one resolved now.
		if let statsNode = latestLocalStatsNodeNum, statsNode != radioNum {
			latestLocalStats = nil
			latestLocalStatsNodeNum = nil
		}

		// The reads run on a context of their own, off the main thread: they only read, and
		// they return plain values, so nothing here touches a model object afterwards.
		let container = PersistenceController.shared.container
		let generation = PersistenceController.shared.containerGeneration
		let needsStoredStats = latestLocalStats == nil
		let data = await Task.detached(priority: .utility) {
			Self.readDatabase(container: container, radioNum: radioNum, needsStoredStats: needsStoredStats)
		}.value
		// The store was reset while reading; what was read belongs to the old one. Build again
		// from the new store.
		guard generation == PersistenceController.shared.containerGeneration else {
			pendingTriggers.formUnion(triggers)
			retry(after: 0)
			return
		}

		// Fall back to the newest stored LocalStats telemetry when none has
		// arrived in this session yet (fresh connect). One that arrived while
		// reading is newer and wins.
		if latestLocalStats == nil, let stored = data.storedLocalStats, let radioNum {
			latestLocalStats = stored
			latestLocalStatsNodeNum = radioNum
		}

		let nodes = data.nodes
		let unreadChannels = data.unreadChannels
		let unreadDMs = data.unreadDMs
		let recent = data.recentMessages

		let snapshot = WidgetSnapshot(
			generatedAt: .now,
			connectionState: connectionState,
			radioNodeNum: radioNum,
			radioLongName: data.radioLongName,
			radioShortName: data.radioShortName,
			radioBatteryLevel: data.radioBatteryLevel,
			localStats: latestLocalStats,
			nodes: nodes,
			totalNodeCount: data.totalNodeCount,
			unreadChannelMessages: unreadChannels,
			unreadDirectMessages: unreadDMs,
			recentMessages: recent
		)
		WidgetSnapshotStore.save(snapshot)
		MeshLiveActivityManager.shared.meshStatusDidUpdate(snapshot)
		// The map renderer throttles itself; it only redraws when pins moved.
		WidgetMapRenderer.shared.refresh(nodes: nodes, radioNum: radioNum)
		// Catches up after launch or install; the save hook covers new routes.
		WidgetTraceRouteRenderer.shared.refresh()

		let connectionKey = "\(connectionState.rawValue)|\(radioNum ?? -1)"
		let connectionChanged = connectionKey != lastWrittenConnectionKey
		lastWrittenConnectionKey = connectionKey

		let messagesKey = "\(unreadChannels)|\(unreadDMs)|\(recent.first?.messageId ?? 0)"
		let messagesChanged = messagesKey != lastWrittenMessagesKey
		lastWrittenMessagesKey = messagesKey

		reloadKinds(for: triggers, connectionChanged: connectionChanged, messagesChanged: messagesChanged)
	}

	/// What the snapshot needs from the database, as plain values.
	private struct DatabaseRead: Sendable {
		var radioLongName: String?
		var radioShortName: String?
		var radioBatteryLevel: Int32?
		var storedLocalStats: LocalStatsSnapshot?
		var nodes: [NodeSnapshot] = []
		var totalNodeCount = 0
		var unreadChannels = 0
		var unreadDMs = 0
		var recentMessages: [MessageSnapshot] = []
	}

	nonisolated private static func readDatabase(container: ModelContainer, radioNum: Int64?, needsStoredStats: Bool) -> DatabaseRead {
		let context = ModelContext(container)
		var read = DatabaseRead()
		let radioNode = radioNum.flatMap { getNodeInfo(id: $0, context: context) }
		read.radioLongName = radioNode?.user?.longName
		read.radioShortName = radioNode?.user?.shortName
		read.radioBatteryLevel = radioNode?.latestDeviceMetrics?.batteryLevel

		// Fetched with the backfill-aware helper, never the telemetries inverse
		// relationship — ingest deliberately leaves it nil and faulting it loads
		// every row (#2485), and rows from pre-nodeNum builds are only reachable
		// through the helper until the backfill completes.
		if needsStoredStats, let radioNum {
			var statsDescriptor = FetchDescriptor<TelemetryEntity>(
				predicate: TelemetryEntity.predicate(forNode: radioNum, metricsType: 4),
				sortBy: [SortDescriptor(\.time, order: .reverse)]
			)
			statsDescriptor.fetchLimit = 1
			// Rows with no timestamp (pre-dating current ingest) are skipped —
			// a .distantPast statsAt renders as a multi-millennium age.
			if let stored = try? context.fetch(statsDescriptor).first, let statsTime = stored.time {
				read.storedLocalStats = LocalStatsSnapshot(
					statsAt: statsTime,
					uptimeSeconds: stored.uptimeSeconds,
					channelUtilization: stored.channelUtilization,
					airUtilTx: stored.airUtilTx,
					packetsSent: stored.numPacketsTx,
					packetsReceived: stored.numPacketsRx,
					packetsReceivedBad: stored.numPacketsRxBad,
					packetsReceivedDupe: stored.numRxDupe,
					packetsRelayed: stored.numTxRelay,
					packetsRelayCanceled: stored.numTxRelayCanceled,
					nodesOnline: stored.numOnlineNodes,
					nodesTotal: stored.numTotalNodes
				)
			}
		}

		let preset = (radioNode?.loRaConfig?.modemPreset).flatMap { ModemPresets(rawValue: Int($0)) }
		read.nodes = fetchNodeSnapshots(context: context, preset: preset, radioNum: radioNum)
		read.totalNodeCount = (try? context.fetchCount(FetchDescriptor<NodeInfoEntity>())) ?? read.nodes.count
		(read.unreadChannels, read.unreadDMs) = fetchUnreadCounts(context: context)
		read.recentMessages = fetchRecentMessages(context: context, radioNum: radioNum, radioNode: radioNode)
		return read
	}

	private static func connectionState(for manager: AccessoryManager) -> WidgetConnectionState {
		if manager.isConnected { return .connected }
		if manager.isConnecting { return .connecting }
		return .disconnected
	}

	nonisolated private static func fetchNodeSnapshots(context: ModelContext, preset: ModemPresets?, radioNum: Int64?) -> [NodeSnapshot] {
		// Two fetches: favorites by the scalar flag (so an offline favorite is
		// never lost to the recency window), then the most recently heard.
		// No `user != nil` in either predicate — optional-relationship nil
		// comparisons in #Predicate crash SwiftData on iOS 26; filter in Swift.
		let favoritesDescriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.favorite == true },
			sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
		)
		let favorites = ((try? context.fetch(favoritesDescriptor)) ?? [])
			.filter { $0.user != nil }

		var recentDescriptor = FetchDescriptor<NodeInfoEntity>(
			sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
		)
		recentDescriptor.fetchLimit = 60
		let recent = ((try? context.fetch(recentDescriptor)) ?? [])
			.filter { $0.user != nil && !$0.favorite }

		let ordered = favorites + recent
		var selected = Array(ordered.prefix(24))
		// The tracker measures distance from the radio's own node, so the radio
		// must survive the cap even when favorites alone fill it.
		if let radioNum, !selected.contains(where: { $0.num == radioNum }) {
			let radioDescriptor = FetchDescriptor<NodeInfoEntity>(
				predicate: #Predicate<NodeInfoEntity> { $0.num == radioNum }
			)
			if let radioNode = try? context.fetch(radioDescriptor).first, radioNode.user != nil {
				selected.append(radioNode)
			}
		}
		return selected.map { node in
			// Same display gate the app uses for signal: SNR present and not MQTT.
			let hasSignal = node.snr != 0 && !node.viaMqtt
			let rating: Int? = (hasSignal && preset != nil)
				? getLoRaSignalStrength(snr: node.snr, rssi: node.rssi, preset: preset!).rawValue
				: nil
			// nodeCoordinate nil-guards the 0/0 a positionless node stores —
			// the raw latitude accessor returns 0, not nil.
			let coordinate = node.latestPosition?.nodeCoordinate
			return NodeSnapshot(
				num: node.num,
				longName: node.user?.longName ?? "Unknown".localized,
				shortName: node.user?.shortName ?? "?",
				colorSeed: UInt32(truncatingIfNeeded: node.num),
				batteryLevel: node.latestDeviceMetrics?.batteryLevel,
				snr: hasSignal ? node.snr : nil,
				rssi: hasSignal ? node.rssi : nil,
				signalRating: rating,
				lastHeard: node.lastHeard,
				isOnline: node.isOnline,
				hopsAway: node.hopsAway,
				latitude: coordinate?.latitude,
				longitude: coordinate?.longitude,
				isFavorite: node.favorite
			)
		}
	}

	/// Same fetch-and-split approach as AppState.refreshBadgeCount — comparing an
	/// optional relationship to nil inside a #Predicate crashes SwiftData on iOS 26.
	nonisolated private static func fetchUnreadCounts(context: ModelContext) -> (channels: Int, dms: Int) {
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { $0.isEmoji == false && $0.read == false }
		)
		// Loaded with the messages, rather than one at a time below.
		descriptor.relationshipKeyPathsForPrefetching = [\.toUser]
		let unread = (try? context.fetch(descriptor)) ?? []
		let channels = unread.filter { $0.toUser == nil }.count
		let dms = unread.filter { $0.toUser != nil && !$0.admin }.count
		return (channels, dms)
	}

	nonisolated private static func fetchRecentMessages(context: ModelContext, radioNum: Int64?, radioNode: NodeInfoEntity?) -> [MessageSnapshot] {
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { $0.isEmoji == false && $0.admin == false },
			sortBy: [SortDescriptor(\.messageTimestamp, order: .reverse)]
		)
		// messageId uniqueness is only enforced per save, so a sent message and
		// its mesh echo can coexist briefly; fetch extra and dedupe below.
		descriptor.fetchLimit = 16
		let fetched = (try? context.fetch(descriptor)) ?? []

		var channelNames: [Int32: String] = [:]
		for channel in radioNode?.myInfo?.channels ?? [] where channel.role > 0 {
			let fallback = channel.index == 0 ? "Primary" : "Channel \(channel.index)"
			channelNames[channel.index] = (channel.name?.isEmpty ?? true) ? fallback : channel.name!
		}

		var seenIds = Set<Int64>()
		var snapshots: [MessageSnapshot] = []
		for message in fetched {
			guard snapshots.count < 8 else { break }
			guard let fromUser = message.fromUser,
				  seenIds.insert(message.messageId).inserted else { continue }
			let kind: MessageSnapshot.Kind
			if let toUser = message.toUser {
				// Show the conversation partner, not ourselves, for sent DMs.
				let partner = fromUser.num == radioNum ? toUser.num : fromUser.num
				kind = .directMessage(userNum: partner)
			} else {
				let name = channelNames[message.channel] ?? "Channel \(message.channel)"
				kind = .channel(index: message.channel, name: name)
			}
			snapshots.append(MessageSnapshot(
				messageId: message.messageId,
				kind: kind,
				senderShortName: fromUser.shortName ?? "?",
				senderLongName: fromUser.longName ?? "Unknown".localized,
				senderColorSeed: UInt32(truncatingIfNeeded: fromUser.num),
				text: message.messagePayload ?? "",
				timestamp: Date(timeIntervalSince1970: TimeInterval(message.messageTimestamp)),
				isUnread: !message.read
			))
		}
		return snapshots
	}

	// MARK: - Reloads

	/// Minimum seconds between reloads, per kind, unioned across the window's
	/// triggers (smallest floor wins). A connection trigger only earns the
	/// immediate plan when (state, radio) actually changed — BLE reconnect
	/// storms fire updateState far more often than the state value moves — and
	/// a messages trigger only when the unread counts or newest message moved,
	/// so a busy channel can't exhaust the WidgetKit reload budget.
	private func reloadKinds(for triggers: Set<Trigger>, connectionChanged: Bool, messagesChanged: Bool) {
		var floors: [Kind: TimeInterval] = [:]
		func merge(_ plan: [(Kind, TimeInterval)]) {
			for (kind, floor) in plan {
				floors[kind] = min(floors[kind] ?? .infinity, floor)
			}
		}
		// WidgetMapRenderer reloads the map kind when it writes a new image. The
		// map's counts and connection tag come from this snapshot, so it also
		// reloads here, at long floors: a connection change right away, the
		// online count at most every 15 minutes.
		for trigger in triggers {
			switch trigger {
			case .connection:
				merge(connectionChanged
					? [(.stats, 0), (.tracker, 0), (.messages, 0), (.map, 0)]
					: [(.stats, 300), (.tracker, 300), (.messages, 300), (.map, 900)])
			case .config:
				merge([(.stats, 60), (.tracker, 60), (.map, 900)])
			case .messages:
				merge(messagesChanged
					? [(.messages, 0), (.tracker, 300)]
					: [(.messages, 300), (.tracker, 300)])
			case .localStats:
				merge([(.stats, 300), (.tracker, 300), (.map, 900)])
			}
		}
		for (kind, floor) in floors {
			let last = lastReload[kind] ?? .distantPast
			guard Date().timeIntervalSince(last) >= floor else { continue }
			// A map render in progress reloads the map itself when it's written,
			// with the counts too; reloading now would spend a second reload on
			// the old image. If the render fails it sends this one instead.
			if kind == .map, WidgetMapRenderer.shared.isRendering {
				mapReloadDeferred = true
				continue
			}
			reload(kind)
		}
	}

	/// Called by WidgetMapRenderer when a render ends without writing, so a map
	/// reload held back for it still goes out.
	func sendDeferredMapReload() {
		guard mapReloadDeferred else { return }
		reload(.map)
	}

	/// Reloads a widget kind and records it, so every reload of the kind counts
	/// toward its floor, whoever asked for it.
	func reload(_ kind: Kind) {
		if kind == .map { mapReloadDeferred = false }
		lastReload[kind] = Date()
		WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
	}
}
