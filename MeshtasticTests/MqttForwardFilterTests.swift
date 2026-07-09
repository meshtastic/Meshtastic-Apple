//
//  MqttForwardFilterTests.swift
//  MeshtasticTests
//
//  Coverage for the MQTT client-proxy downlink filter (MqttForwardFilter). In
//  client-proxy mode the public broker floods payload-less packet-header stubs
//  the node cannot use; the filter drops those before they cost BLE bandwidth,
//  while always forwarding real traffic and the PKI / own-echo guard cases.
//

import Testing
import Foundation
@testable import Meshtastic
import MeshtasticProtobufs

@Suite("MQTT Forward Filter")
struct MqttForwardFilterTests {

	/// Builds a ServiceEnvelope for the filter under test.
	/// - `hasPacket == false` leaves the inner packet unset (envelope.hasPacket == false).
	private func makeEnvelope(
		gatewayID: String = "!aabbccdd",
		channelID: String = "LongFast",
		hasPacket: Bool = true,
		payload: MeshPacket.OneOf_PayloadVariant? = nil
	) -> ServiceEnvelope {
		var env = ServiceEnvelope()
		env.gatewayID = gatewayID
		env.channelID = channelID
		if hasPacket {
			var pkt = MeshPacket()
			if let payload {
				pkt.payloadVariant = payload
			}
			env.packet = pkt
		}
		return env
	}

	private let myHex = "!433e2700"

	// MARK: - Real payloads are always forwarded

	@Test("Decoded payload is forwarded")
	func decodedForwarded() {
		let env = makeEnvelope(payload: .decoded(DataMessage()))
		#expect(MqttForwardFilter.decide(envelope: env, myNodeHex: myHex) == .forward)
	}

	@Test("Encrypted payload is forwarded")
	func encryptedForwarded() {
		let env = makeEnvelope(payload: .encrypted(Data([0x01, 0x02, 0x03])))
		#expect(MqttForwardFilter.decide(envelope: env, myNodeHex: myHex) == .forward)
	}

	// MARK: - Tier 1: payload-less stubs are dropped

	@Test("Payload-less packet is dropped")
	func payloadlessDropped() {
		// The observed LongFast flood: a packet with no payload variant.
		let env = makeEnvelope(payload: nil)
		#expect(MqttForwardFilter.decide(envelope: env, myNodeHex: myHex) == .dropNoPayload)
	}

	// MARK: - Guards: never drop

	@Test("PKI topic is never dropped, even when payload-less")
	func pkiGuard() {
		let env = makeEnvelope(channelID: "PKI", payload: nil)
		#expect(MqttForwardFilter.decide(envelope: env, myNodeHex: myHex) == .forward)
	}

	@Test("Own echo (gateway == my node) is never dropped, even when payload-less")
	func ownEchoGuard() {
		let env = makeEnvelope(gatewayID: myHex, payload: nil)
		#expect(MqttForwardFilter.decide(envelope: env, myNodeHex: myHex) == .forward)
	}

	@Test("Own-echo guard is case-insensitive")
	func ownEchoGuardCaseInsensitive() {
		let env = makeEnvelope(gatewayID: "!433E2700", payload: nil)
		#expect(MqttForwardFilter.decide(envelope: env, myNodeHex: myHex) == .forward)
	}

	@Test("A different gateway's payload-less packet is still dropped")
	func otherGatewayDropped() {
		let env = makeEnvelope(gatewayID: "!deadbeef", payload: nil)
		#expect(MqttForwardFilter.decide(envelope: env, myNodeHex: myHex) == .dropNoPayload)
	}

	@Test("Unknown local node id does not suppress dropping")
	func emptyMyHexDrops() {
		// Empty hex must never accidentally match a gateway id.
		let env = makeEnvelope(gatewayID: "!deadbeef", payload: nil)
		#expect(MqttForwardFilter.decide(envelope: env, myNodeHex: "") == .dropNoPayload)
	}

	// MARK: - Fail open

	@Test("Envelope with no packet is forwarded (fail open)")
	func noPacketForwarded() {
		let env = makeEnvelope(hasPacket: false)
		#expect(MqttForwardFilter.decide(envelope: env, myNodeHex: myHex) == .forward)
	}
}
