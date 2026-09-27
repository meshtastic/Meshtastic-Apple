//
//  MultiRadioMqttTests.swift
//  MeshtasticTests
//
//  Feature 021, T100: the MQTT client proxy's shared packet handling, and each additional
//  radio's own proxy.
//

import CocoaMQTT
import Foundation
import MeshtasticProtobufs
import Testing
@testable import Meshtastic

private actor SentRecorder: Connection {
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

@Suite("MQTT proxy packets")
struct MqttProxyPacketsTests {

	private func envelope(hopLimit: UInt32, withPayload: Bool = true) throws -> Data {
		var envelope = ServiceEnvelope()
		envelope.channelID = "LongFast"
		envelope.gatewayID = "!12345678"
		var packet = MeshPacket()
		packet.from = 0x1234_5678
		packet.hopLimit = hopLimit
		packet.hopStart = 3
		if withPayload {
			packet.encrypted = Data([1, 2, 3])
		}
		envelope.packet = packet
		return try envelope.serializedData()
	}

	@Test("Stat topics and payload-less packets are dropped")
	func drops() throws {
		#expect(MqttProxyPackets.downlink(topic: "msh/2/stat/!1234", payload: Data(), retained: false, myNodeNum: 0) == .dropStat)
		let stub = try envelope(hopLimit: 0, withPayload: false)
		#expect(MqttProxyPackets.downlink(topic: "msh/2/e/LongFast/!12345678", payload: stub, retained: false, myNodeNum: 0) == .dropNoPayload)
	}

	@Test("The hop limit is clamped to 0, and the rest of the packet is kept")
	func clampsHopLimit() throws {
		let data = try envelope(hopLimit: 2)
		guard case .forward(let toRadio, let zeroed) = MqttProxyPackets.downlink(topic: "msh/2/e/LongFast/!12345678", payload: data, retained: true, myNodeNum: 0xABCD) else {
			Issue.record("expected a forward")
			return
		}
		#expect(zeroed == 2)
		let proxy = toRadio.mqttClientProxyMessage
		#expect(proxy.topic == "msh/2/e/LongFast/!12345678")
		#expect(proxy.retained)
		let forwarded = try ServiceEnvelope(serializedBytes: proxy.data)
		#expect(forwarded.packet.hopLimit == 0)
		#expect(forwarded.packet.hopStart == 3)
		#expect(forwarded.packet.encrypted == Data([1, 2, 3]))
	}

	@Test("Unparseable bytes are forwarded unchanged")
	func failsOpen() {
		let junk = Data([0xFF, 0xFF, 0xFF])
		guard case .forward(let toRadio, let zeroed) = MqttProxyPackets.downlink(topic: "msh/json", payload: junk, retained: false, myNodeNum: 0) else {
			Issue.record("expected a forward")
			return
		}
		#expect(zeroed == nil)
		#expect(toRadio.mqttClientProxyMessage.data == junk)
	}

	@Test("Uplink takes binary or text payloads, and nothing without one")
	func uplink() {
		var binary = MqttClientProxyMessage()
		binary.topic = "msh/2/e/LongFast/!0000abcd"
		binary.data = Data([9, 8, 7])
		#expect(MqttProxyPackets.uplink(binary)?.payload == [9, 8, 7])

		var text = MqttClientProxyMessage()
		text.topic = "msh/2/json"
		text.text = "{}"
		#expect(MqttProxyPackets.uplink(text)?.payload == Array("{}".utf8))

		var empty = MqttClientProxyMessage()
		empty.topic = "msh/none"
		#expect(MqttProxyPackets.uplink(empty) == nil)
	}
}

@MainActor
@Suite("Additional radio MQTT proxy", .serialized, .timeLimit(.minutes(1)))
struct AdditionalRadioMqttTests {

	@Test("Broker traffic goes to that radio's own connection, filtered like the focused radio's")
	func downlinkReachesTheRadio() async throws {
		let connection = SentRecorder()
		var device = Device(id: UUID(), name: "Extra", transportType: .tcp, identifier: "b.local:4403")
		device.num = 0x0B0B
		let radio = RadioSession(device: device, connection: connection)
		let bridge = AdditionalRadioMqttBridge(radio: radio)

		var envelope = ServiceEnvelope()
		envelope.channelID = "LongFast"
		var packet = MeshPacket()
		packet.hopLimit = 3
		packet.encrypted = Data([4])
		envelope.packet = packet
		let payload = [UInt8](try envelope.serializedData())
		bridge.onMqttMessageReceived(message: CocoaMQTTMessage(topic: "msh/2/e/LongFast/!1", payload: payload))
		bridge.onMqttMessageReceived(message: CocoaMQTTMessage(topic: "msh/2/stat/!1", payload: [1]))

		var waited = 0
		while await connection.sent.isEmpty, waited < 100 {
			try await Task.sleep(for: .milliseconds(10))
			waited += 1
		}
		let sent = await connection.sent
		#expect(sent.count == 1)
		let forwarded = try ServiceEnvelope(serializedBytes: try #require(sent.first).mqttClientProxyMessage.data)
		#expect(forwarded.packet.hopLimit == 0)
		bridge.stop()
		#expect(!bridge.isConnected)
	}

	@Test("A radio without MQTT proxy to client gets no proxy")
	func noProxyWithoutTheSetting() async {
		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		var device = Device(id: UUID(), name: "Extra", transportType: .tcp, identifier: "b.local:4403")
		device.num = 0x7E57_0100
		let radio = RadioSession(device: device, connection: SentRecorder())
		manager.additionalRadios[device.id] = radio

		await manager.startAdditionalMqtt(radio)
		#expect(radio.mqtt == nil)
	}
}
