//
//  NodeHopsAndSignalTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

/// Hops away, via MQTT, signal and last heard as stored from the node db download and from received packets.
@Suite("Node hops and signal")
struct NodeHopsAndSignalTests {

	private let num: Int64 = 0x00E0_0301
	private let heardAt = Date(timeIntervalSince1970: 1_780_000_000)

	@MainActor
	private func makeStore() throws -> (MeshPackets, ModelContainer) {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		return (MeshPackets(modelContainer: container), container)
	}

	@MainActor
	private func fetchNode(_ container: ModelContainer) throws -> NodeInfoEntity? {
		let num = num
		return try ModelContext(container).fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })).first
	}

	private func nodeInfo(hops: UInt32? = nil, viaMqtt: Bool = false) -> NodeInfo {
		var info = NodeInfo()
		info.num = UInt32(num)
		info.lastHeard = UInt32(heardAt.timeIntervalSince1970)
		info.snr = 6.5
		info.viaMqtt = viaMqtt
		if let hops { info.hopsAway = hops }
		return info
	}

	/// A packet as a live LoRa reception carries it on firmware 2.8.
	private func livePacket(rxTime: Date, hops: UInt32 = 2, snr: Float = 4.25, rssi: Int32 = -90) -> MeshPacket {
		var packet = MeshPacket()
		packet.from = UInt32(num)
		packet.rxTime = UInt32(rxTime.timeIntervalSince1970)
		packet.transportMechanism = .transportLora
		packet.rxSnr = snr
		packet.rxRssi = rssi
		packet.hopStart = 7
		packet.hopLimit = 7 - hops
		return packet
	}

	/// A stored packet the radio resends after the node db: marked LoRa, no RSSI, the old receive time.
	private func replayedPacket(rxTime: Date, hops: UInt32) -> MeshPacket {
		var packet = MeshPacket()
		packet.from = UInt32(num)
		packet.rxTime = UInt32(rxTime.timeIntervalSince1970)
		packet.transportMechanism = .transportLora
		packet.rxSnr = 1.0
		packet.hopStart = 3
		packet.hopLimit = 3 - hops
		return packet
	}

	private func apply(_ packet: MeshPacket, _ mp: MeshPackets) async {
		await mp.updateAnyPacketFrom(packet: packet, activeDeviceNum: 1)
		await mp.flushDebouncedSaves()
	}

	// MARK: Node db download

	@Test @MainActor func aNewNodeWithoutHopsAwayKeepsTheDefault() async throws {
		let (mp, container) = try makeStore()
		let info = nodeInfo()
		#expect(!info.hasHopsAway)
		_ = await mp.nodeInfoPacket(nodeInfo: info, channel: 0)
		#expect(try fetchNode(container)?.hopsAway == NodeInfoEntity().hopsAway)
	}

	@Test @MainActor func anEntryWithoutHopsAwayKeepsTheStoredValue() async throws {
		let (mp, container) = try makeStore()
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 3), channel: 0)
		#expect(try fetchNode(container)?.hopsAway == 3)

		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(), channel: 0)
		#expect(try fetchNode(container)?.hopsAway == 3, "unknown must not become 0, which means direct")

		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 0), channel: 0)
		#expect(try fetchNode(container)?.hopsAway == 0, "a sent 0 is a real direct reception")
	}

	@Test @MainActor func viaMqttIsTakenFromTheNodeDb() async throws {
		let (mp, container) = try makeStore()
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 0, viaMqtt: true), channel: 0)
		#expect(try fetchNode(container)?.viaMqtt == true)

		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 0, viaMqtt: false), channel: 0)
		#expect(try fetchNode(container)?.viaMqtt == false)

		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 1, viaMqtt: true), channel: 0)
		#expect(try fetchNode(container)?.viaMqtt == true, "the existing node path sets it too")
	}

	// MARK: Received packets

	@Test @MainActor func aLivePacketUpdatesSignalHopsAndLastHeard() async throws {
		let (mp, container) = try makeStore()
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 5), channel: 0)

		let later = heardAt.addingTimeInterval(600)
		await apply(livePacket(rxTime: later, hops: 2), mp)
		let node = try #require(try fetchNode(container))
		#expect(node.snr == 4.25)
		#expect(node.rssi == -90)
		#expect(node.hopsAway == 2)
		#expect(node.lastHeard == later)
		#expect(!node.viaMqtt)
	}

	@Test @MainActor func aReplayedPacketChangesNothingItCannotKnow() async throws {
		let (mp, container) = try makeStore()
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 5), channel: 0)
		let later = heardAt.addingTimeInterval(600)
		await apply(livePacket(rxTime: later, hops: 5), mp)

		await apply(replayedPacket(rxTime: heardAt.addingTimeInterval(-3_600), hops: 3), mp)
		let node = try #require(try fetchNode(container))
		#expect(node.snr == 4.25)
		#expect(node.rssi == -90)
		#expect(node.hopsAway == 5)
		#expect(node.lastHeard == later)
	}

	@Test @MainActor func aReplayWithoutReceiveTimeDoesNotMarkTheNodeHeardNow() async throws {
		let (mp, container) = try makeStore()
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 1), channel: 0)
		var replay = replayedPacket(rxTime: heardAt, hops: 0)
		replay.rxTime = 0
		replay.hopStart = 0
		replay.hopLimit = 0
		await apply(replay, mp)
		#expect(try fetchNode(container)?.lastHeard == heardAt)
	}

	@Test @MainActor func anOlderLivePacketDoesNotMoveLastHeardBack() async throws {
		let (mp, container) = try makeStore()
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 1), channel: 0)
		await apply(livePacket(rxTime: heardAt.addingTimeInterval(-60), hops: 1, snr: -3, rssi: -110), mp)
		let node = try #require(try fetchNode(container))
		#expect(node.lastHeard == heardAt)
		#expect(node.snr == -3, "the signal is still a real reading")
	}

	@Test @MainActor func aLivePacketReplacesALastHeardInTheFuture() async throws {
		let (mp, container) = try makeStore()
		var info = nodeInfo(hops: 1)
		info.lastHeard = UInt32(Date().addingTimeInterval(86_400 * 365 * 5).timeIntervalSince1970)
		_ = await mp.nodeInfoPacket(nodeInfo: info, channel: 0)
		let now = Date()
		await apply(livePacket(rxTime: now, hops: 1), mp)
		let node = try #require(try fetchNode(container))
		#expect(node.lastHeard.map { abs($0.timeIntervalSince(now)) < 1 } == true, "a time from a wrong clock must not stick")
	}

	@Test @MainActor func aLivePacketAtZeroDbmIsAReading() async throws {
		let (mp, container) = try makeStore()
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 1), channel: 0)
		await apply(livePacket(rxTime: heardAt.addingTimeInterval(60), hops: 0, snr: 12, rssi: 0), mp)
		let node = try #require(try fetchNode(container))
		#expect(node.snr == 12)
		#expect(node.rssi == 0)
		#expect(node.hopsAway == 0)
	}

	@Test @MainActor func anMqttPacketSetsTheFlagHopsAndLastHeardButNotSignal() async throws {
		let (mp, container) = try makeStore()
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 4), channel: 0)
		await apply(livePacket(rxTime: heardAt.addingTimeInterval(60), hops: 4), mp)

		var mqtt = MeshPacket()
		mqtt.from = UInt32(num)
		mqtt.rxTime = UInt32(heardAt.addingTimeInterval(120).timeIntervalSince1970)
		mqtt.transportMechanism = .transportMqtt
		mqtt.viaMqtt = true
		mqtt.hopStart = 3
		mqtt.hopLimit = 2
		await apply(mqtt, mp)

		let node = try #require(try fetchNode(container))
		#expect(node.viaMqtt)
		#expect(node.hopsAway == 1, "hops to the gateway, as the radio stores them")
		#expect(node.lastHeard == heardAt.addingTimeInterval(120))
		#expect(node.snr == 4.25)
		#expect(node.rssi == -90)
	}

	@Test @MainActor func anImplicitAckDoesNotTouchLastHeard() async throws {
		let (mp, container) = try makeStore()
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(hops: 2), channel: 0)

		var ack = MeshPacket()
		ack.from = UInt32(num)
		ack.decoded.portnum = .routingApp
		await apply(ack, mp)
		let node = try #require(try fetchNode(container))
		#expect(node.lastHeard == heardAt)
		#expect(node.snr == 6.5)
		#expect(node.hopsAway == 2)
	}
}
