//
//  MultiRadioAdminRoutingTests.swift
//  MeshtasticTests
//
//  Feature 021, T089: which connected radio an admin packet goes through, and the relaying
//  radio's own session passkey.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

private actor AdminRecorder: Connection {
	let type: TransportType = .tcp
	var isConnected = true
	private(set) var sent: [ToRadio] = []

	func send(_ data: ToRadio) async throws { sent.append(data) }
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws { isConnected = false }
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("Multi-radio admin routing", .serialized)
struct MultiRadioAdminRoutingTests {

	private let firstNum: Int64 = 0x0A0A
	private let extraNum: Int64 = 0x0B0B
	private let remoteNum: Int64 = 0x7E57_0200

	private struct Fixture {
		let manager: AccessoryManager
		let context: ModelContext
		let first: AdminRecorder
		let extra: AdminRecorder
		let extraSession: RadioSession
	}

	private func makeFixture() throws -> Fixture {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let container = try ModelContainer(for: schema, configurations: ModelConfiguration("AdminRoute-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true))
		let context = ModelContext(container)
		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		manager.context = context
		let first = AdminRecorder()
		var firstDevice = Device(id: UUID(), name: "First", transportType: .tcp, identifier: "a.local:4403")
		firstDevice.num = firstNum
		manager.activeConnection = RadioSession(device: firstDevice, connection: first)
		let extra = AdminRecorder()
		var extraDevice = Device(id: UUID(), name: "Extra", transportType: .tcp, identifier: "b.local:4403")
		extraDevice.num = extraNum
		let extraSession = RadioSession(device: extraDevice, connection: extra)
		manager.additionalRadios[extraDevice.id] = extraSession
		return Fixture(manager: manager, context: context, first: first, extra: extra, extraSession: extraSession)
	}

	private func adminPacket(from: Int64, to: Int64, passkey: Data) throws -> MeshPacket {
		var admin = AdminMessage()
		admin.getDeviceMetadataRequest = true
		admin.sessionPasskey = passkey
		var packet = MeshPacket()
		packet.from = UInt32(from)
		packet.to = UInt32(to)
		packet.decoded.portnum = .adminApp
		packet.decoded.payload = try admin.serializedData()
		return packet
	}

	@Test("Admin to another connected radio goes over its own connection; remote admin follows `from`")
	func routes() throws {
		let fixture = try makeFixture()
		let manager = fixture.manager
		// Settings configuring radio B: from the first radio, to B.
		#expect(manager.adminRoute(for: try adminPacket(from: firstNum, to: extraNum, passkey: Data())) === fixture.extraSession)
		// Remote admin relayed by B, and by the first radio.
		#expect(manager.adminRoute(for: try adminPacket(from: extraNum, to: remoteNum, passkey: Data())) === fixture.extraSession)
		#expect(manager.adminRoute(for: try adminPacket(from: firstNum, to: remoteNum, passkey: Data())) === manager.activeConnection)
		// The first radio itself.
		#expect(manager.adminRoute(for: try adminPacket(from: firstNum, to: firstNum, passkey: Data())) === manager.activeConnection)
	}

	@Test("Remote admin relayed by another radio carries that radio's passkey; local admin is untouched")
	func relayPasskey() throws {
		let fixture = try makeFixture()
		let manager = fixture.manager
		let observation = NodeObservationEntity(radioNum: extraNum, nodeNum: remoteNum)
		observation.sessionPasskey = Data([0xB0, 0xB1])
		fixture.context.insert(observation)
		try fixture.context.save()

		let relayed = manager.adminPacket(try adminPacket(from: extraNum, to: remoteNum, passkey: Data([0xA0])), relayedBy: fixture.extraSession)
		#expect(try AdminMessage(serializedBytes: relayed.decoded.payload).sessionPasskey == Data([0xB0, 0xB1]))

		// Addressed to B itself: local admin, left alone.
		let local = try adminPacket(from: firstNum, to: extraNum, passkey: Data([0xA0]))
		#expect(manager.adminPacket(local, relayedBy: fixture.extraSession) == local)

		// Through the first radio: the node's own passkey, as before.
		let firstSession = try #require(manager.activeConnection)
		let viaFirst = try adminPacket(from: firstNum, to: remoteNum, passkey: Data([0xA0]))
		#expect(manager.adminPacket(viaFirst, relayedBy: firstSession) == viaFirst)
	}

	@Test("A metadata request for radio B goes out on B's connection, not the first radio's")
	func requestReachesTheRadio() async throws {
		let fixture = try makeFixture()
		let manager = fixture.manager
		manager.isConnected = true
		let fromUser = UserEntity()
		fromUser.num = firstNum
		let toUser = UserEntity()
		toUser.num = extraNum

		_ = try await manager.requestDeviceMetadata(fromUser: fromUser, toUser: toUser)

		let sent = await fixture.extra.sent
		#expect(sent.count == 1)
		#expect(sent.first?.packet.to == UInt32(extraNum))
		#expect(await fixture.first.sent.isEmpty)
	}
}
