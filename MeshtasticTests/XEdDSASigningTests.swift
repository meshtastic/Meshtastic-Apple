// XEdDSASigningTests.swift
// MeshtasticTests
//
// Covers the XEdDSA packet-signing flags surfaced in the UI (design#113 / issue #1992):
//   - MeshPacket.xeddsa_signed (field 22)  → MessageEntity.xeddsaSigned
//   - NodeInfo.has_xeddsa_signed (field 14) → NodeInfoEntity.hasXeddsaSigned
// These fields come from the upstream-generated 2.8 protobuf sources; the tests guard their
// binary wire compatibility and our ingestion behavior, independent of how the code is generated.

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("XEdDSA signing")
struct XEdDSASigningTests {

	// MARK: - Protobuf wire round-trip (guards wire compatibility of both fields)

	@Test func meshPacket_xeddsaSigned_roundTrips() throws {
		var packet = MeshPacket()
		packet.from = 0x1234
		packet.id = 42
		packet.xeddsaSigned = true

		let bytes = try packet.serializedData()
		let decoded = try MeshPacket(serializedData: bytes)

		#expect(decoded.xeddsaSigned == true)
		#expect(decoded.from == 0x1234)
		#expect(decoded.id == 42)
	}

	@Test func meshPacket_xeddsaSigned_defaultsFalseAndStaysOffWire() throws {
		let packet = MeshPacket()
		#expect(packet.xeddsaSigned == false)
		// Default false must not be emitted on the wire (proto3 default-omission).
		let bytes = try packet.serializedData()
		let decoded = try MeshPacket(serializedData: bytes)
		#expect(decoded.xeddsaSigned == false)
	}

	@Test func nodeInfo_hasXeddsaSigned_roundTrips() throws {
		var nodeInfo = NodeInfo()
		nodeInfo.num = 0xABCD
		nodeInfo.hasXeddsaSigned_p = true

		let bytes = try nodeInfo.serializedData()
		let decoded = try NodeInfo(serializedData: bytes)

		#expect(decoded.hasXeddsaSigned_p == true)
		#expect(decoded.num == 0xABCD)
	}

	@Test func nodeInfo_hasXeddsaSigned_defaultsFalse() throws {
		let nodeInfo = NodeInfo()
		#expect(nodeInfo.hasXeddsaSigned_p == false)
	}

	// MARK: - Protobuf wire bytes (pin the field numbers + default omission)
	//
	// Encode→decode round-trips alone would still pass if the field number changed or if `false`
	// started being emitted, so assert the exact emitted bytes for the isolated field instead.

	@Test func meshPacket_xeddsaSigned_emitsField22Tag() throws {
		var packet = MeshPacket()
		packet.xeddsaSigned = true
		// field 22, varint wire type: tag = (22 << 3) | 0 = 176 → varint [0xB0, 0x01]; value true = 0x01.
		#expect(Array(try packet.serializedData()) == [0xB0, 0x01, 0x01])
	}

	@Test func meshPacket_defaultFalse_omitsField22() throws {
		// proto3 omits a false bool, so an otherwise-empty packet serializes to nothing on the wire.
		#expect(try MeshPacket().serializedData().isEmpty)
	}

	@Test func nodeInfo_hasXeddsaSigned_emitsField14Tag() throws {
		var nodeInfo = NodeInfo()
		nodeInfo.hasXeddsaSigned_p = true
		// field 14, varint wire type: tag = (14 << 3) | 0 = 112 = 0x70; value true = 0x01.
		#expect(Array(try nodeInfo.serializedData()) == [0x70, 0x01])
	}

	@Test func nodeInfo_defaultFalse_omitsField14() throws {
		#expect(try NodeInfo().serializedData().isEmpty)
	}

	// MARK: - Entity defaults

	@Test @MainActor func messageEntity_xeddsaSigned_defaultsFalse() throws {
		let context = TestContainerProvider.shared.mainContext
		let message = MessageEntity()
		context.insert(message)
		#expect(message.xeddsaSigned == false)
		message.xeddsaSigned = true
		#expect(message.xeddsaSigned == true)
	}

	@Test @MainActor func nodeInfoEntity_hasXeddsaSigned_defaultsFalse() throws {
		let context = TestContainerProvider.shared.mainContext
		let node = NodeInfoEntity()
		context.insert(node)
		#expect(node.hasXeddsaSigned == false)
		node.hasXeddsaSigned = true
		#expect(node.hasXeddsaSigned == true)
	}
}

// MARK: - Ingestion behavior

/// Exercises the actual packet→entity ingestion logic that the UI depends on:
/// the broadcast-only gate for the message shield and the latch for the node row.
@Suite("XEdDSA ingestion")
struct XEdDSAIngestionTests {

	@MainActor
	private func fetchNode(_ num: Int64) -> NodeInfoEntity? {
		let ctx = ModelContext(sharedModelContainer)
		return try? ctx.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })).first
	}

	@MainActor
	private func fetchMessage(_ id: Int64) -> MessageEntity? {
		let ctx = ModelContext(sharedModelContainer)
		return try? ctx.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == id })).first
	}

	private func nodeInfo(num: UInt32, signed: Bool) -> NodeInfo {
		var ni = NodeInfo()
		ni.num = num
		ni.hasXeddsaSigned_p = signed
		return ni
	}

	private func packet(id: UInt32, from: UInt32, to: UInt32, signed: Bool, decoded: DataMessage) -> MeshPacket {
		var packet = MeshPacket()
		packet.id = id
		packet.from = from
		packet.to = to
		packet.channel = 0
		packet.decoded = decoded
		packet.xeddsaSigned = signed
		return packet
	}

	private func textPacket(id: UInt32, from: UInt32, to: UInt32, signed: Bool) -> MeshPacket {
		var data = DataMessage()
		data.portnum = .textMessageApp
		data.payload = Data("hi".utf8)
		return packet(id: id, from: from, to: to, signed: signed, decoded: data)
	}

	/// A store-and-forward *router text broadcast*: addressed to the local node (not the broadcast
	/// address) yet semantically a channel broadcast, carried as a StoreAndForward payload.
	private func storeForwardBroadcastPacket(id: UInt32, from: UInt32, to: UInt32, signed: Bool) -> MeshPacket {
		var sf = StoreAndForward()
		sf.rr = .routerTextBroadcast
		sf.text = Data("hi".utf8)
		var data = DataMessage()
		data.portnum = .storeForwardApp
		data.payload = (try? sf.serializedData()) ?? Data()
		return packet(id: id, from: from, to: to, signed: signed, decoded: data)
	}

	// MARK: node-level flag (NodeInfo.has_xeddsa_signed → NodeInfoEntity.hasXeddsaSigned)

	@Test @MainActor func nodeInfoPacket_setsFlag_whenNodeSigns() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let num: Int64 = 0x00E0_0101
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(num: UInt32(num), signed: true), channel: 0)
		#expect(fetchNode(num)?.hasXeddsaSigned == true)
	}

	@Test @MainActor func nodeInfoPacket_leavesFlagFalse_whenNodeUnsigned() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let num: Int64 = 0x00E0_0102
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(num: UInt32(num), signed: false), channel: 0)
		#expect(fetchNode(num)?.hasXeddsaSigned == false)
	}

	/// The node flag means "≥1 verified" and persists — a later NodeInfo that omits the bit
	/// must not downgrade a node we've already seen sign.
	@Test @MainActor func nodeInfoPacket_latchesFlag_acrossUpdates() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let num: Int64 = 0x00E0_0103
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(num: UInt32(num), signed: true), channel: 0)
		_ = await mp.nodeInfoPacket(nodeInfo: nodeInfo(num: UInt32(num), signed: false), channel: 0)
		#expect(fetchNode(num)?.hasXeddsaSigned == true)
	}

	// MARK: per-message flag — broadcast only, never DMs (MeshPacket.xeddsa_signed)

	@Test @MainActor func textMessage_signedBroadcast_setsFlag() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let id: Int64 = 0x00B0_0201
		let packet = textPacket(id: UInt32(id), from: 0xA01, to: Constants.maximumNodeNum, signed: true)
		await mp.textMessageAppPacket(packet: packet, wantRangeTestPackets: true, connectedNode: 0x01, appState: nil)
		#expect(fetchMessage(id)?.xeddsaSigned == true)
	}

	/// Firmware never sets the flag on DMs, but the ingest path also gates on the broadcast
	/// address so a stray/spoofed signed DM can never light the "verified" shield.
	@Test @MainActor func textMessage_signedDirectMessage_doesNotSetFlag() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let id: Int64 = 0x00B0_0202
		let packet = textPacket(id: UInt32(id), from: 0xA02, to: 0x01, signed: true)
		await mp.textMessageAppPacket(packet: packet, wantRangeTestPackets: true, connectedNode: 0x01, appState: nil)
		#expect(fetchMessage(id)?.xeddsaSigned == false)
	}

	/// A signed store-and-forward router broadcast is addressed to the local node (to != broadcast
	/// address) but is a channel broadcast, so its verified shield must survive the broadcast gate.
	@Test @MainActor func storeForwardBroadcast_signed_setsFlag() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let id: Int64 = 0x00B0_0203
		let packet = storeForwardBroadcastPacket(id: UInt32(id), from: 0xA03, to: 0x01, signed: true)
		await mp.textMessageAppPacket(packet: packet, wantRangeTestPackets: true, connectedNode: 0x01, storeForward: true, appState: nil)
		#expect(fetchMessage(id)?.xeddsaSigned == true)
	}
}
