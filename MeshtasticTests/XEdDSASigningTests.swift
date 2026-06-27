// XEdDSASigningTests.swift
// MeshtasticTests
//
// Covers the XEdDSA packet-signing flags surfaced in the UI (design#113 / issue #1992):
//   - MeshPacket.xeddsa_signed (field 22)  → MessageEntity.xeddsaSigned
//   - NodeInfo.has_xeddsa_signed (field 14) → NodeInfoEntity.hasXeddsaSigned
// The protobuf fields are hand-added to the generated sources, so these tests also guard the
// binary wire round-trip for both fields.

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("XEdDSA signing")
struct XEdDSASigningTests {

	// MARK: - Protobuf wire round-trip (guards the hand-edited generated code)

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
