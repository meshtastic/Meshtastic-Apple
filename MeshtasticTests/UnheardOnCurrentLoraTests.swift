//
//  UnheardOnCurrentLoraTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/4/26.
//
import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

/// NodeInfo.heard_on_current_lora, per meshtastic/design#146.
@Suite("Unheard on current LoRa settings")
struct UnheardOnCurrentLoraTests {

	@MainActor
	private func fetchNode(_ num: Int64) -> NodeInfoEntity? {
		let ctx = ModelContext(sharedModelContainer)
		return try? ctx.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })).first
	}

	private func nodeInfo(num: UInt32, heard: Bool) -> NodeInfo {
		var info = NodeInfo()
		info.num = num
		info.heardOnCurrentLora = heard
		return info
	}

	// MARK: Firmware gate

	@Test func onlyFirmware281AndLaterReportsTheField() {
		#expect(AccessoryManager.reportsHeardOnCurrentLora(firmwareVersion: "2.8.1"))
		#expect(AccessoryManager.reportsHeardOnCurrentLora(firmwareVersion: "2.8.1.54e0d8d"))
		#expect(AccessoryManager.reportsHeardOnCurrentLora(firmwareVersion: "2.9.0"))
		#expect(AccessoryManager.reportsHeardOnCurrentLora(firmwareVersion: "3.0.0"))
		#expect(!AccessoryManager.reportsHeardOnCurrentLora(firmwareVersion: "2.8.0"))
		#expect(!AccessoryManager.reportsHeardOnCurrentLora(firmwareVersion: "2.7.26.54e0d8d"))
	}

	@Test func anUnknownVersionDoesNotReportTheField() {
		// Older firmware never sends it and it reads false, so guessing would mark every node.
		#expect(!AccessoryManager.reportsHeardOnCurrentLora(firmwareVersion: nil))
		#expect(!AccessoryManager.reportsHeardOnCurrentLora(firmwareVersion: ""))
		#expect(!AccessoryManager.reportsHeardOnCurrentLora(firmwareVersion: "unknown"))
	}

	// MARK: Marker

	@Test func onlyAnRFNodeReportedFalseIsMarked() {
		let node = NodeInfoEntity()
		node.heardOnCurrentLora = false
		#expect(node.isUnheardOnCurrentLora)

		node.viaMqtt = true
		#expect(!node.isUnheardOnCurrentLora, "an MQTT node never reaches the radio over RF")

		node.viaMqtt = false
		node.heardOnCurrentLora = nil
		#expect(!node.isUnheardOnCurrentLora, "unknown is not unheard")

		node.heardOnCurrentLora = true
		#expect(!node.isUnheardOnCurrentLora)
	}

	// MARK: Ingest

	@Test @MainActor func nodeDbDumpStoresTheFieldOnlyFromAReportingRadio() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let num: Int64 = 0x00E0_0201

		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(num: UInt32(num), heard: false), channel: 0)
		#expect(fetchNode(num)?.heardOnCurrentLora == nil)

		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(num: UInt32(num), heard: false), channel: 0,
									reportsHeardOnCurrentLora: true)
		#expect(fetchNode(num)?.heardOnCurrentLora == false)

		// A downgraded radio stops sending it; the stored answer must not outlive that.
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(num: UInt32(num), heard: false), channel: 0)
		#expect(fetchNode(num)?.heardOnCurrentLora == nil)
	}

	@Test func theRadiosOwnEntryIsNeverMarked() {
		let info = nodeInfo(num: 0x0000_0042, heard: false)
		#expect(MeshPackets.heardOnCurrentLora(info, reported: true, connectedNodeNum: 0x42) == nil)
		#expect(MeshPackets.heardOnCurrentLora(info, reported: true, connectedNodeNum: 0x43) == false)
	}

	@Test @MainActor func aPacketHeardOverRFClearsTheMarker() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let num: Int64 = 0x00E0_0202
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(num: UInt32(num), heard: false), channel: 0,
									reportsHeardOnCurrentLora: true)

		var viaMqtt = MeshPacket()
		viaMqtt.from = UInt32(num)
		viaMqtt.rxTime = UInt32(Date().timeIntervalSince1970)
		viaMqtt.viaMqtt = true
		await mp.updateAnyPacketFrom(packet: viaMqtt, activeDeviceNum: 1, reportsHeardOnCurrentLora: true)
		await mp.flushDebouncedSaves()
		#expect(fetchNode(num)?.heardOnCurrentLora == false, "MQTT says nothing about the radio's channel")

		// The radio replays stored packets after a node db download: marked LoRa, but no RSSI.
		var replayed = viaMqtt
		replayed.viaMqtt = false
		replayed.transportMechanism = .transportLora
		await mp.updateAnyPacketFrom(packet: replayed, activeDeviceNum: 1, reportsHeardOnCurrentLora: true)
		await mp.flushDebouncedSaves()
		#expect(fetchNode(num)?.heardOnCurrentLora == false, "a replayed packet was heard earlier, not now")

		// A measured 0 dBm is a real reception.
		var overRF = replayed
		overRF.rxRssi = 0
		#expect(overRF.hasRxRssi)
		await mp.updateAnyPacketFrom(packet: overRF, activeDeviceNum: 1, reportsHeardOnCurrentLora: true)
		await mp.flushDebouncedSaves()
		#expect(fetchNode(num)?.heardOnCurrentLora == true)
	}

	// MARK: Row refresh

	/// The row rebuilds its snapshot when this key changes. The radio's answer can change on
	/// reconnect without a new packet, so the marker would otherwise stay stale.
	@Test @MainActor func theRowRefreshKeyFollowsTheRadiosAnswer() {
		let node = NodeInfoEntity()
		node.lastHeard = Date(timeIntervalSince1970: 1_000)
		node.heardOnCurrentLora = true
		let before = NodeRowRefreshKey(node)
		node.heardOnCurrentLora = false
		#expect(NodeRowRefreshKey(node) != before)
	}

	@Test @MainActor func aNodeMissingFromTheDumpLosesItsAnswer() async throws {
		// Own container: the sweep touches every node, so it must not see other tests' nodes.
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let mp = MeshPackets(modelContainer: container)
		let kept: Int64 = 0x00E0_0203
		let gone: Int64 = 0x00E0_0204
		for num in [kept, gone] {
			_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(num: UInt32(num), heard: true), channel: 0,
										reportsHeardOnCurrentLora: true)
		}

		await mp.markAbsentFromRadio(presentNums: [kept])
		let ctx = ModelContext(container)
		let nodes = try ctx.fetch(FetchDescriptor<NodeInfoEntity>())
		#expect(nodes.count == 2, "only the answer is cleared; the node stays")
		#expect(nodes.first { $0.num == kept }?.heardOnCurrentLora == true)
		#expect(nodes.first { $0.num == gone }?.heardOnCurrentLora == nil)
	}

	// MARK: Filter

	@Test @MainActor func theFilterHidesOnlyMarkedNodes() throws {
		let store = try #require(UserDefaults(suiteName: "UnheardOnCurrentLoraTests.filter"))
		store.removePersistentDomain(forName: "UnheardOnCurrentLoraTests.filter")
		let filters = NodeFilterParameters(store: store)

		let unheard = NodeInfoEntity()
		unheard.heardOnCurrentLora = false
		let unknown = NodeInfoEntity()

		#expect(filters.matches(unheard))
		filters.hidesUnheardOnCurrentLora = true
		#expect(filters.isFiltering)
		#expect(!filters.matches(unheard))
		#expect(filters.matches(unknown))

		filters.reset()
		#expect(!filters.hidesUnheardOnCurrentLora)
	}

	// MARK: Aggregate offer

	/// From a real store after a preset change: the radio reported on about 120 of the app's 260
	/// nodes. Counting all 260 hid the notice with 118 of the 120 unheard.
	@Test func mostOfTheListCountsOnlyNodesTheRadioReportedOn() {
		#expect(UnheardOnCurrentLoraOffer.isMostOfList(unheard: 118, reported: 120))
		#expect(!UnheardOnCurrentLoraOffer.isMostOfList(unheard: 10, reported: 120))
		#expect(!UnheardOnCurrentLoraOffer.isMostOfList(unheard: 0, reported: 0))
	}

	@Test func keepHidesTheOfferUntilTheCountGrows() throws {
		let store = try #require(UserDefaults(suiteName: "UnheardOnCurrentLoraTests.offer"))
		store.removePersistentDomain(forName: "UnheardOnCurrentLoraTests.offer")
		#expect(UnheardOnCurrentLoraOffer.shouldOffer(count: 40, forNode: 7, store: store))
		UnheardOnCurrentLoraOffer.dismiss(count: 40, forNode: 7, store: store)
		#expect(!UnheardOnCurrentLoraOffer.shouldOffer(count: 40, forNode: 7, store: store))
		#expect(!UnheardOnCurrentLoraOffer.shouldOffer(count: 12, forNode: 7, store: store))
		#expect(UnheardOnCurrentLoraOffer.shouldOffer(count: 41, forNode: 7, store: store))
	}

	@Test func keepResetsOnceFewerNodesAreUnheard() throws {
		let store = try #require(UserDefaults(suiteName: "UnheardOnCurrentLoraTests.lower"))
		store.removePersistentDomain(forName: "UnheardOnCurrentLoraTests.lower")
		UnheardOnCurrentLoraOffer.dismiss(count: 208, forNode: 7, store: store)
		#expect(!UnheardOnCurrentLoraOffer.shouldOffer(count: 60, forNode: 7, store: store))

		// Back on a preset the nodes are heard on.
		UnheardOnCurrentLoraOffer.lowerDismissal(toCount: 0, forNode: 7, store: store)
		#expect(UnheardOnCurrentLoraOffer.shouldOffer(count: 60, forNode: 7, store: store))

		// A higher count never raises it.
		UnheardOnCurrentLoraOffer.lowerDismissal(toCount: 60, forNode: 7, store: store)
		#expect(UnheardOnCurrentLoraOffer.shouldOffer(count: 1, forNode: 7, store: store))
	}

	// MARK: LoRa change in progress

	@Test func aBurstOfChangesWaitsForTheNewestDownload() {
		var tracker = LoRaChangeNodeDatabaseTracker()
		#expect(!tracker.isAwaiting)

		let first = tracker.changed()
		#expect(tracker.isAwaiting)
		let askedFirst = tracker.request(first)
		#expect(askedFirst)

		// Changed again while the first download runs.
		let second = tracker.changed()
		let third = tracker.changed()
		tracker.finished(first)
		#expect(tracker.isAwaiting, "the first download was for older settings")

		let askedSecond = tracker.request(second)
		#expect(!askedSecond, "a newer change asks instead")
		let askedThird = tracker.request(third)
		#expect(askedThird)
		#expect(tracker.isAwaiting)
		tracker.finished(third)
		#expect(!tracker.isAwaiting)
	}

	@Test func onlyTheNewestRequestEndsTheWait() {
		var tracker = LoRaChangeNodeDatabaseTracker()
		let change = tracker.changed()
		// Its wait isn't over yet, so a completion for it doesn't count.
		tracker.finished(change)
		#expect(tracker.isAwaiting)
		let asked = tracker.request(change)
		#expect(asked)
		tracker.finished(change)
		#expect(!tracker.isAwaiting)
	}

	@Test func disconnectingEndsTheWait() {
		var tracker = LoRaChangeNodeDatabaseTracker()
		let change = tracker.changed()
		let asked = tracker.request(change)
		#expect(asked)
		tracker.reset()
		#expect(!tracker.isAwaiting)
	}

	@Test func aSaveFinishingAfterADisconnectDoesNotEndANewWait() {
		var tracker = LoRaChangeNodeDatabaseTracker()
		let beforeDisconnect = tracker.changed()
		let askedBefore = tracker.request(beforeDisconnect)
		#expect(askedBefore)
		tracker.reset()

		let afterReconnect = tracker.changed()
		let askedAfter = tracker.request(afterReconnect)
		#expect(askedAfter)
		tracker.finished(beforeDisconnect)
		#expect(tracker.isAwaiting)
		tracker.finished(afterReconnect)
		#expect(!tracker.isAwaiting)
	}

	@Test func aFullRemovalSaysNothingAndAPartialOneSaysWhy() {
		#expect(UnheardNodesStrings.removalResult(removed: 40, keptAsHeard: 0, failed: 0) == nil)
		let partial = UnheardNodesStrings.removalResult(removed: 19, keptAsHeard: 63, failed: 0)
		#expect(partial?.contains("19") == true)
		#expect(partial?.contains("63") == true)
		#expect(UnheardNodesStrings.removalResult(removed: 0, keptAsHeard: 0, failed: 2) != nil)
	}
}
