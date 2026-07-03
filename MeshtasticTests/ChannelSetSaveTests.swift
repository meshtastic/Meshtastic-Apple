//
//  ChannelSetSaveTests.swift
//  MeshtasticTests
//
//  Regression coverage for issue #2010: applying a QR-generated channel set that
//  makes substantial LoRa changes reboots the device and drops the connection.
//  The save must NOT surface that expected disconnect as "Failed to save channel
//  configuration", and the LoRa config must be transmitted exactly once (the
//  duplicate send block introduced in #1682).
//

import Testing
import Foundation
import SwiftData
@testable import Meshtastic
import MeshtasticProtobufs

enum MockChannelSetFailureMode: Sendable, Equatable {
	case firstPacket
	case wantConfig
}

/// Minimal in-memory `Connection` that drives `AccessoryManager.saveChannelSet`
/// without any real BLE/TCP transport.
///
/// It models the real failure window: the radio accepts the channel and LoRa
/// packets, then reboots after the substantial LoRa change. By the time the app
/// follows up with its `wantConfig`, the link is gone — so this mock throws on
/// the `wantConfig` send to reproduce the post-reboot disconnect.
actor MockChannelSetConnection: Connection {
	let type: TransportType = .ble
	var isConnected: Bool = true
	let failureMode: MockChannelSetFailureMode

	/// Every `ToRadio` handed to the transport, in send order.
	private(set) var sentPackets: [ToRadio] = []

	init(failureMode: MockChannelSetFailureMode = .wantConfig) {
		self.failureMode = failureMode
	}

	/// Number of `setConfig.lora` admin packets actually transmitted.
	var loraConfigSendCount: Int {
		sentPackets.reduce(into: 0) { count, toRadio in
			guard case let .packet(meshPacket) = toRadio.payloadVariant,
				  case let .decoded(dataMessage) = meshPacket.payloadVariant,
				  let admin = try? AdminMessage(serializedBytes: dataMessage.payload),
				  case let .setConfig(config) = admin.payloadVariant,
				  case .lora = config.payloadVariant else { return }
			count += 1
		}
	}

	func send(_ data: ToRadio) async throws {
		sentPackets.append(data)
		if failureMode == .firstPacket, case .packet = data.payloadVariant {
			throw AccessoryError.connectionFailed("Simulated channel send failure")
		}
		if case .wantConfigID = data.payloadVariant {
			// The device rebooted after the LoRa config change; the link is gone.
			if failureMode == .wantConfig {
				isConnected = false
				throw AccessoryError.connectionFailed("Simulated reboot disconnect")
			}
		}
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
@Suite("Channel Set Save (issue #2010)", .serialized)
struct ChannelSetSaveTests {

	/// Builds a base64url ChannelSet string carrying one channel and, by default, a
	/// reboot-worthy LoRa config — the shape produced by a real "local mesh" QR code.
	/// Pass `includeLoRaConfig: false` for a channels-only share link.
	private func makeChannelSet(includeLoRaConfig: Bool = true, channelNames: [String] = ["TestNet"]) -> ChannelSet {
		var channelSet = ChannelSet()
		channelSet.settings = channelNames.map { name in
			var settings = ChannelSettings()
			settings.name = name
			return settings
		}

		if includeLoRaConfig {
			var lora = Config.LoRaConfig()
			lora.usePreset = true
			lora.region = .us
			lora.modemPreset = .longFast
			lora.hopLimit = 3
			channelSet.loraConfig = lora
		}

		return channelSet
	}

	private func makeChannelSetLink(includeLoRaConfig: Bool = true, channelNames: [String] = ["TestNet"]) throws -> String {
		let channelSet = makeChannelSet(includeLoRaConfig: includeLoRaConfig, channelNames: channelNames)
		let data = try channelSet.serializedData()
		return data.base64EncodedString().base64ToBase64url()
	}

	private func makeManager(
		connection: MockChannelSetConnection,
		deviceNum: Int64 = 123_456_789,
		activeDeviceNum: Int64? = nil
	) -> AccessoryManager {
		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(),
			name: "Test RAK4631",
			transportType: .ble,
			identifier: "test-rak4631",
			connectionState: .connected,
			num: deviceNum
		)
		manager.activeConnection = (device: device, connection: connection)
		manager.activeDeviceNum = activeDeviceNum
		return manager
	}

	private func seedMyInfo(deviceNum: Int64, channelName: String) throws {
		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == deviceNum })
		for existing in try context.fetch(descriptor) {
			context.delete(existing)
		}
		try context.save()

		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = deviceNum
		let channel = ChannelEntity()
		channel.id = 0
		channel.index = 0
		channel.name = channelName
		channel.role = Int32(Channel.Role.primary.rawValue)
		context.insert(myInfo)
		context.insert(channel)
		myInfo.channels.append(channel)
		try context.save()
		MeshPackets.recreateShared()
	}

	private func channelNames(for deviceNum: Int64) throws -> [String] {
		let context = ModelContext(PersistenceController.shared.container)
		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == deviceNum })
		return try context.fetch(descriptor).first?.channels
			.sorted { $0.index < $1.index }
			.map { $0.name ?? "" } ?? []
	}

	@Test("Saving a QR channel set survives the post-reboot disconnect without erroring")
	func testSaveSurvivesRebootDisconnect() async throws {
		let connection = MockChannelSetConnection()
		let manager = makeManager(connection: connection)
		let link = try makeChannelSetLink()

		// Regression for #2010: the device reboots after the LoRa config change and the
		// connection drops; the follow-up wantConfig failure must NOT bubble up as a save
		// failure. Before the fix this threw, surfacing "Failed to save channel configuration"
		// even though the config had already been delivered.
		try await manager.saveChannelSet(base64UrlString: link, addChannels: false, okToMQTT: false)
	}

	@Test("LoRa config is transmitted exactly once during a replace-all channel save")
	func testLoRaConfigSentExactlyOnce() async throws {
		let connection = MockChannelSetConnection()
		let manager = makeManager(connection: connection)
		let link = try makeChannelSetLink()

		try await manager.saveChannelSet(base64UrlString: link, addChannels: false, okToMQTT: false)

		// Regression for the duplicated LoRa send block (#1682): the config must be sent once.
		let count = await connection.loraConfigSendCount
		#expect(count == 1)
	}

	@Test("A malformed channel-set link throws instead of silently succeeding")
	func testMalformedLinkThrows() async throws {
		let connection = MockChannelSetConnection()
		let manager = makeManager(connection: connection)

		// Regression: before the fix, an undecodable link cleared local channels and
		// returned success without ever contacting the device. It must now throw, and
		// nothing should have been put on the wire.
		await #expect(throws: (any Error).self) {
			try await manager.saveChannelSet(base64UrlString: "!!!not-valid-base64!!!", addChannels: false, okToMQTT: false)
		}
		let sent = await connection.sentPackets
		#expect(sent.isEmpty)
	}

	@Test("A channels-only replace does not push a LoRa config to the radio")
	func testReplaceWithoutLoRaConfigDoesNotSendLoRa() async throws {
		let connection = MockChannelSetConnection()
		let manager = makeManager(connection: connection)
		let link = try makeChannelSetLink(includeLoRaConfig: false)

		// No embedded LoRa config: the device must not be sent a default-initialized
		// LoRaConfig (which would reset its region/frequency). A replace with no LoRa
		// config is rejected before anything reaches the wire.
		await #expect(throws: (any Error).self) {
			try await manager.saveChannelSet(base64UrlString: link, addChannels: false, okToMQTT: false)
		}

		let count = await connection.loraConfigSendCount
		#expect(count == 0)
		let sent = await connection.sentPackets
		#expect(sent.isEmpty)
	}

	@Test("Duplicate incoming channel names are rejected before radio writes")
	func testDuplicateIncomingChannelNamesThrowBeforeSending() async throws {
		let connection = MockChannelSetConnection()
		let manager = makeManager(connection: connection)
		let channelSet = makeChannelSet(channelNames: ["SameName", "SameName"])

		await #expect(throws: (any Error).self) {
			try await manager.saveChannelSet(channelSet: channelSet, addChannels: false, okToMQTT: false)
		}

		let sent = await connection.sentPackets
		#expect(sent.isEmpty)
	}

	@Test("Failed replace send leaves existing local channels intact")
	func testFailedReplaceSendDoesNotClearLocalChannels() async throws {
		let deviceNum: Int64 = 123_456_790
		try seedMyInfo(deviceNum: deviceNum, channelName: "Existing")
		let connection = MockChannelSetConnection(failureMode: .firstPacket)
		let manager = makeManager(connection: connection, deviceNum: deviceNum)
		let channelSet = makeChannelSet(channelNames: ["Imported"])

		await #expect(throws: (any Error).self) {
			try await manager.saveChannelSet(channelSet: channelSet, addChannels: false, okToMQTT: false)
		}

		#expect(try channelNames(for: deviceNum) == ["Existing"])
	}

	@Test("Local channel upsert uses the connected device number")
	func testLocalChannelUpsertUsesConnectedDeviceNumber() async throws {
		let connectedDeviceNum: Int64 = 123_456_791
		let staleDeviceNum: Int64 = 123_456_792
		try seedMyInfo(deviceNum: connectedDeviceNum, channelName: "Connected")
		try seedMyInfo(deviceNum: staleDeviceNum, channelName: "Stale")
		let connection = MockChannelSetConnection()
		let manager = makeManager(
			connection: connection,
			deviceNum: connectedDeviceNum,
			activeDeviceNum: staleDeviceNum
		)
		let channelSet = makeChannelSet(channelNames: ["Imported"])

		try await manager.saveChannelSet(channelSet: channelSet, addChannels: false, okToMQTT: false)

		#expect(try channelNames(for: connectedDeviceNum) == ["Imported"])
		#expect(try channelNames(for: staleDeviceNum) == ["Stale"])
	}
}
