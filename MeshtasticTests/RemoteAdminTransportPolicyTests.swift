//
//  RemoteAdminTransportPolicyTests.swift
//  MeshtasticTests
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

actor RecordingRemoteAdminConnection: Connection {
	let type: TransportType = .ble
	var isConnected = true
	private(set) var sentPackets: [ToRadio] = []

	func send(_ data: ToRadio) async throws {
		sentPackets.append(data)
	}

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		AsyncStream { $0.finish() }
	}

	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {}
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("Licensed remote Admin transport", .serialized)
struct RemoteAdminTransportPolicyTests {

	private enum TestError: Error {
		case missingMeshPacket
	}

	private func makeManager(
		connectedDeviceNum: Int64,
		connection: RecordingRemoteAdminConnection
	) -> AccessoryManager {
		let manager = AccessoryManager(transports: [])
		manager.context = sharedModelContainer.mainContext
		manager.activeDeviceNum = connectedDeviceNum
		manager.activeConnection = (
			device: Device(
				id: UUID(),
				name: "Test radio",
				transportType: .ble,
				identifier: "remote-admin-\(connectedDeviceNum)",
				connectionState: .connected,
				num: connectedDeviceNum
			),
			connection: connection
		)
		return manager
	}

	private func user(num: Int64, isLicensed: Bool) throws -> UserEntity {
		let context = sharedModelContainer.mainContext
		let requestedNum = num
		var descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == requestedNum })
		descriptor.fetchLimit = 1
		let result = try context.fetch(descriptor).first ?? UserEntity()
		if result.modelContext == nil {
			result.num = num
			context.insert(result)
		}
		result.isLicensed = isLicensed
		try context.save()
		return result
	}

	private func removeUser(num: Int64) throws {
		let context = sharedModelContainer.mainContext
		let requestedNum = num
		let descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == requestedNum })
		for existing in try context.fetch(descriptor) {
			context.delete(existing)
		}
		try context.save()
	}

	private func adminPacket(from: Int64, to: Int64) -> ToRadio {
		var decoded = DataMessage()
		decoded.portnum = .adminApp

		var packet = MeshPacket()
		packet.from = UInt32(truncatingIfNeeded: from)
		packet.to = UInt32(truncatingIfNeeded: to)
		packet.channel = 7
		packet.pkiEncrypted = true
		packet.publicKey = Data([0x01, 0x02, 0x03])
		packet.decoded = decoded

		var toRadio = ToRadio()
		toRadio.packet = packet
		return toRadio
	}

	private func lastMeshPacket(from connection: RecordingRemoteAdminConnection) async throws -> MeshPacket {
		guard let toRadio = await connection.sentPackets.last,
			  case let .packet(packet) = toRadio.payloadVariant
		else { throw TestError.missingMeshPacket }
		return packet
	}

	@Test("Licensed remote Admin clears PKI fields at the final send boundary")
	func licensedRemoteAdminIsPlaintext() async throws {
		let ownerNum: Int64 = 4_010_000_001
		let remoteNum: Int64 = 4_010_000_002
		_ = try user(num: ownerNum, isLicensed: true)
		let connection = RecordingRemoteAdminConnection()
		let manager = makeManager(connectedDeviceNum: ownerNum, connection: connection)

		try await manager.send(adminPacket(from: ownerNum, to: remoteNum))

		let packet = try await lastMeshPacket(from: connection)
		#expect(packet.channel == 0)
		#expect(packet.pkiEncrypted == false)
		#expect(packet.publicKey.isEmpty)
	}

	@Test("The shared Admin helper also records a plaintext licensed remote request")
	func sharedAdminHelperIsPlaintext() async throws {
		let ownerNum: Int64 = 4_010_000_003
		let remoteNum: Int64 = 4_010_000_004
		let owner = try user(num: ownerNum, isLicensed: true)
		let remote = try user(num: remoteNum, isLicensed: false)
		let connection = RecordingRemoteAdminConnection()
		let manager = makeManager(connectedDeviceNum: ownerNum, connection: connection)

		try await manager.requestDeviceConfig(fromUser: owner, toUser: remote)

		let packet = try await lastMeshPacket(from: connection)
		#expect(packet.decoded.portnum == .adminApp)
		#expect(packet.channel == 0)
		#expect(packet.pkiEncrypted == false)
		#expect(packet.publicKey.isEmpty)
	}

	@Test("Normal-mode remote Admin preserves existing packet fields")
	func normalRemoteAdminIsUnchanged() async throws {
		let ownerNum: Int64 = 4_010_000_005
		let remoteNum: Int64 = 4_010_000_006
		_ = try user(num: ownerNum, isLicensed: false)
		let connection = RecordingRemoteAdminConnection()
		let manager = makeManager(connectedDeviceNum: ownerNum, connection: connection)

		try await manager.send(adminPacket(from: ownerNum, to: remoteNum))

		let packet = try await lastMeshPacket(from: connection)
		#expect(packet.channel == 7)
		#expect(packet.pkiEncrypted)
		#expect(packet.publicKey == Data([0x01, 0x02, 0x03]))
	}

	@Test("Licensed self Admin preserves existing packet fields")
	func licensedSelfAdminIsUnchanged() async throws {
		let ownerNum: Int64 = 4_010_000_007
		_ = try user(num: ownerNum, isLicensed: true)
		let connection = RecordingRemoteAdminConnection()
		let manager = makeManager(connectedDeviceNum: ownerNum, connection: connection)

		try await manager.send(adminPacket(from: ownerNum, to: ownerNum))

		let packet = try await lastMeshPacket(from: connection)
		#expect(packet.channel == 7)
		#expect(packet.pkiEncrypted)
		#expect(packet.publicKey == Data([0x01, 0x02, 0x03]))
	}

	@Test("Unknown connected-owner mode does not assume licensed transport")
	func unknownOwnerModeIsUnchanged() async throws {
		let ownerNum: Int64 = 4_010_000_008
		let remoteNum: Int64 = 4_010_000_009
		try removeUser(num: ownerNum)
		let connection = RecordingRemoteAdminConnection()
		let manager = makeManager(connectedDeviceNum: ownerNum, connection: connection)

		try await manager.send(adminPacket(from: ownerNum, to: remoteNum))

		let packet = try await lastMeshPacket(from: connection)
		#expect(packet.channel == 7)
		#expect(packet.pkiEncrypted)
		#expect(packet.publicKey == Data([0x01, 0x02, 0x03]))
	}

	@Test("Remote Admin wording distinguishes signed and PKI modes")
	func conditionalWording() {
		#expect(RemoteAdminWording.activeFormat(localOwnerIsLicensed: true) == "Remote Signed Admin: %@")
		#expect(RemoteAdminWording.requestFormat(localOwnerIsLicensed: true) == "Request Signed Admin: %@")
		#expect(RemoteAdminWording.activeFormat(localOwnerIsLicensed: false) == "Remote PKI Admin: %@")
		#expect(RemoteAdminWording.requestFormat(localOwnerIsLicensed: false) == "Request PKI Admin: %@")
	}
}
