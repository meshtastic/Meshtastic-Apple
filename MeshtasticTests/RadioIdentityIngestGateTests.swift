// RadioIdentityIngestGateTests.swift
// MeshtasticTests

import Foundation
import MeshtasticProtobufs
import Testing
@testable import Meshtastic

@Suite("Radio identity ingest gate", .serialized)
@MainActor
struct RadioIdentityIngestGateTests {
	@Test("radio-owned packets wait for canonical MyInfo")
	func packetsWaitForMyInfo() async {
		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
			name: "Test radio",
			transportType: .ble,
			identifier: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
		)
		manager.activeConnection = (
			device: device,
			connection: MockChannelSetConnection()
		)
		var firstNode = NodeInfo()
		firstNode.num = 42
		var firstPacket = FromRadio()
		firstPacket.payloadVariant = .nodeInfo(firstNode)
		var secondNode = NodeInfo()
		secondNode.num = 43
		var secondPacket = FromRadio()
		secondPacket.payloadVariant = .nodeInfo(secondNode)

		await manager.didReceive(.data(firstPacket))
		await manager.didReceive(.data(secondPacket))

		#expect(!manager.identityConfirmedForConnection)
		#expect(manager.packetsPendingIdentity == [firstPacket, secondPacket])
	}

	@Test("disconnect discards packets when MyInfo never arrives")
	func disconnectDiscardsPendingPackets() async throws {
		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
			name: "Test radio",
			transportType: .ble,
			identifier: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
		)
		manager.activeConnection = (
			device: device,
			connection: MockChannelSetConnection()
		)
		var nodeInfo = NodeInfo()
		nodeInfo.num = 42
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .nodeInfo(nodeInfo)
		await manager.didReceive(.data(fromRadio))

		try await manager.closeConnection()

		#expect(manager.packetsPendingIdentity.isEmpty)
		#expect(!manager.identityConfirmedForConnection)
	}

	@Test("pre-identity packet buffer is bounded")
	func packetBufferIsBounded() async {
		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
			name: "Test radio",
			transportType: .ble,
			identifier: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
		)
		manager.activeConnection = (
			device: device,
			connection: MockChannelSetConnection()
		)
		var nodeInfo = NodeInfo()
		nodeInfo.num = 42
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .nodeInfo(nodeInfo)
		manager.packetsPendingIdentity = Array(
			repeating: fromRadio,
			count: AccessoryManager.maxPacketsPendingIdentity
		)

		await manager.didReceive(.data(fromRadio))

		#expect(manager.packetsPendingIdentity.count == AccessoryManager.maxPacketsPendingIdentity)
		#expect(manager.lastConnectionError != nil)
	}
}
