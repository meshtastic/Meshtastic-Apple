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
@testable import Meshtastic
import MeshtasticProtobufs

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

	/// Every `ToRadio` handed to the transport, in send order.
	private(set) var sentPackets: [ToRadio] = []

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
		if case .wantConfigID = data.payloadVariant {
			// The device rebooted after the LoRa config change; the link is gone.
			isConnected = false
			throw AccessoryError.connectionFailed("Simulated reboot disconnect")
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
@Suite("Channel Set Save (issue #2010)")
struct ChannelSetSaveTests {

	/// Builds a base64url ChannelSet string carrying one channel and, by default, a
	/// reboot-worthy LoRa config — the shape produced by a real "local mesh" QR code.
	/// Pass `includeLoRaConfig: false` for a channels-only share link.
	private func makeChannelSetLink(includeLoRaConfig: Bool = true) throws -> String {
		var primary = ChannelSettings()
		primary.name = "TestNet"

		var channelSet = ChannelSet()
		channelSet.settings = [primary]

		if includeLoRaConfig {
			var lora = Config.LoRaConfig()
			lora.usePreset = true
			lora.region = .us
			lora.modemPreset = .longFast
			lora.hopLimit = 3
			channelSet.loraConfig = lora
		}

		let data = try channelSet.serializedData()
		return data.base64EncodedString().base64ToBase64url()
	}

	private func makeManager(connection: MockChannelSetConnection) -> AccessoryManager {
		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(),
			name: "Test RAK4631",
			transportType: .ble,
			identifier: "test-rak4631",
			connectionState: .connected,
			num: 123_456_789
		)
		manager.activeConnection = (device: device, connection: connection)
		return manager
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
		// LoRaConfig (which would reset its region/frequency). The follow-up wantConfig
		// throws via the mock here — irrelevant to this assertion, so it is ignored.
		try? await manager.saveChannelSet(base64UrlString: link, addChannels: false, okToMQTT: false)

		let count = await connection.loraConfigSendCount
		#expect(count == 0)
	}
}
