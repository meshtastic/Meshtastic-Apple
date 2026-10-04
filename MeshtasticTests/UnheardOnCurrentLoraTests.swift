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

		var overRF = viaMqtt
		overRF.viaMqtt = false
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

	@Test func keepHidesTheOfferUntilTheCountGrows() throws {
		let store = try #require(UserDefaults(suiteName: "UnheardOnCurrentLoraTests.offer"))
		store.removePersistentDomain(forName: "UnheardOnCurrentLoraTests.offer")
		#expect(UnheardOnCurrentLoraOffer.shouldOffer(count: 40, forNode: 7, store: store))
		UnheardOnCurrentLoraOffer.dismiss(count: 40, forNode: 7, store: store)
		#expect(!UnheardOnCurrentLoraOffer.shouldOffer(count: 40, forNode: 7, store: store))
		#expect(!UnheardOnCurrentLoraOffer.shouldOffer(count: 12, forNode: 7, store: store))
		#expect(UnheardOnCurrentLoraOffer.shouldOffer(count: 41, forNode: 7, store: store))
	}
}
