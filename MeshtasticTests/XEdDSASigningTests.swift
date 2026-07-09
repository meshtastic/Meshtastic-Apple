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

// MARK: - Configurable packet authenticity

actor MockSecurityConfigConnection: Connection {
	let type: TransportType = .ble
	let isConnected = true
	private(set) var sentPackets: [ToRadio] = []

	var sentSecurityPolicy: Config.SecurityConfig.PacketSignaturePolicy? {
		for toRadio in sentPackets {
			guard case let .packet(meshPacket) = toRadio.payloadVariant,
				  case let .decoded(dataMessage) = meshPacket.payloadVariant,
				  let admin = try? AdminMessage(serializedBytes: dataMessage.payload),
				  case let .setConfig(config) = admin.payloadVariant,
				  case let .security(security) = config.payloadVariant else { continue }
			return security.packetSignaturePolicy
		}
		return nil
	}

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

@Suite("Packet authenticity policy", .serialized)
struct PacketAuthenticityPolicyTests {

	@Test func balanced_isTheWireDefault() throws {
		let config = Config.SecurityConfig()
		#expect(config.packetSignaturePolicy == .balanced)
		#expect(try config.serializedData().isEmpty)
	}

	@Test func strict_roundTripsOnSecurityConfigField9() throws {
		var config = Config.SecurityConfig()
		config.packetSignaturePolicy = .strict

		let bytes = try config.serializedData()
		let decoded = try Config.SecurityConfig(serializedData: bytes)

		#expect(decoded.packetSignaturePolicy == .strict)
		#expect(Array(bytes) == [0x48, 0x02])
	}

	@Test func deviceMetadata_hasXeddsaRoundTripsOnField14() throws {
		var metadata = DeviceMetadata()
		metadata.hasXeddsa_p = true

		let bytes = try metadata.serializedData()
		let decoded = try DeviceMetadata(serializedData: bytes)

		#expect(decoded.hasXeddsa_p == true)
		#expect(Array(bytes) == [0x70, 0x01])
	}

	@Test func compatible_appliesWithoutConfirmation() {
		var state = PacketAuthenticitySelectionState()
		state.propose(.compatible)

		#expect(state.selected == .compatible)
		#expect(state.pendingStrict == false)
	}

	@Test func strict_requiresConfirmationBeforeApplying() {
		var state = PacketAuthenticitySelectionState()
		state.propose(.strict)

		#expect(state.selected == .balanced)
		#expect(state.pendingStrict == true)

		state.confirmStrict()
		#expect(state.selected == .strict)
		#expect(state.pendingStrict == false)
	}

	@Test func cancellingStrict_preservesCurrentPolicy() {
		var state = PacketAuthenticitySelectionState(selected: .compatible)
		state.propose(.strict)
		state.cancelStrict()

		#expect(state.selected == .compatible)
		#expect(state.pendingStrict == false)
	}

	@Test func alreadyStrict_doesNotPromptAgain() {
		var state = PacketAuthenticitySelectionState(selected: .strict)
		state.propose(.strict)

		#expect(state.selected == .strict)
		#expect(state.pendingStrict == false)
	}

	@Test func pickerOptions_useCompatibleBalancedStrictOrder() {
		#expect(
			Config.SecurityConfig.PacketSignaturePolicy.packetAuthenticityOptions == [
				.compatible,
				.balanced,
				.strict
			]
		)
	}

	@Test @MainActor func persistenceEntities_defaultToBalancedAndUnsupported() {
		let context = TestContainerProvider.shared.mainContext
		let security = SecurityConfigEntity()
		let metadata = DeviceMetadataEntity()
		context.insert(security)
		context.insert(metadata)

		#expect(security.packetSignaturePolicy == 0)
		#expect(metadata.hasXeddsa == false)
	}

	@Test @MainActor func capabilityGate_distinguishesUnknownUnsupportedAndSupported() {
		#expect(PacketAuthenticityCapability(metadata: nil) == .unknown)

		let metadata = DeviceMetadataEntity()
		#expect(PacketAuthenticityCapability(metadata: metadata) == .unsupported)
		#expect(PacketAuthenticityCapability(metadata: metadata).allowsChanges == false)

		metadata.hasXeddsa = true
		#expect(PacketAuthenticityCapability(metadata: metadata) == .supported)
		#expect(PacketAuthenticityCapability(metadata: metadata).allowsChanges == true)
	}

	@Test @MainActor func upsertSecurityConfig_persistsPacketAuthenticityPolicy() async throws {
		let nodeNum: Int64 = 0x00E0_0301
		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		for existing in try context.fetch(descriptor) {
			context.delete(existing)
		}
		try context.save()

		let node = NodeInfoEntity()
		node.num = nodeNum
		context.insert(node)
		try context.save()

		MeshPackets.recreateShared()
		var config = Config.SecurityConfig()
		config.packetSignaturePolicy = .compatible
		await MeshPackets.shared.upsertSecurityConfigPacket(config: config, nodeNum: nodeNum)

		let readContext = ModelContext(PersistenceController.shared.container)
		let stored = try #require(readContext.fetch(descriptor).first?.securityConfig)
		#expect(stored.packetSignaturePolicy == Int32(Config.SecurityConfig.PacketSignaturePolicy.compatible.rawValue))
	}

	@Test @MainActor func saveSecurityConfig_transmitsAndUpdatesPacketAuthenticityPolicy() async throws {
		let nodeNum: Int64 = 0x00E0_0302
		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		for existing in try context.fetch(descriptor) {
			context.delete(existing)
		}
		let userDescriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == nodeNum })
		for existing in try context.fetch(userDescriptor) {
			context.delete(existing)
		}
		try context.save()

		let node = NodeInfoEntity()
		node.num = nodeNum
		let user = UserEntity()
		user.num = nodeNum
		let security = SecurityConfigEntity()
		security.packetSignaturePolicy = Int32(Config.SecurityConfig.PacketSignaturePolicy.compatible.rawValue)
		context.insert(node)
		context.insert(user)
		context.insert(security)
		node.user = user
		node.securityConfig = security
		try context.save()

		let connection = MockSecurityConfigConnection()
		let manager = AccessoryManager(transports: [])
		manager.activeDeviceNum = nodeNum
		manager.activeConnection = (
			device: Device(
				id: UUID(),
				name: "Packet authenticity test",
				transportType: .ble,
				identifier: "packet-authenticity-test",
				connectionState: .connected,
				num: nodeNum
			),
			connection: connection
		)

		var config = Config.SecurityConfig()
		config.packetSignaturePolicy = .strict
		_ = try await manager.saveSecurityConfig(config: config, fromUser: user, toUser: user)

		#expect(await connection.sentSecurityPolicy == .strict)
		let readContext = ModelContext(PersistenceController.shared.container)
		let stored = try #require(readContext.fetch(descriptor).first?.securityConfig)
		#expect(stored.packetSignaturePolicy == Int32(Config.SecurityConfig.PacketSignaturePolicy.strict.rawValue))
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

	// MARK: per-message shield — displayed for broadcast traffic (MeshPacket.xeddsa_signed)

	@Test @MainActor func textMessage_signedBroadcast_setsFlag() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let id: Int64 = 0x00B0_0201
		let packet = textPacket(id: UInt32(id), from: 0xA01, to: Constants.maximumNodeNum, signed: true)
		await mp.textMessageAppPacket(packet: packet, wantRangeTestPackets: true, connectedNode: 0x01, appState: nil)
		#expect(fetchMessage(id)?.xeddsaSigned == true)
	}

	/// Firmware may sign non-PKI unicast traffic, but the message shield intentionally remains a
	/// broadcast-authenticity indicator. Direct-message authentication is represented by the
	/// existing PKI lock state, so a signed unicast packet must not light the broadcast shield.
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
