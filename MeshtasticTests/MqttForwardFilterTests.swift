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

	private enum MqttForwardAdmissionTestError: Error {
		case disconnected
	}

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

	@Test("Busy gate rejects before building forwarded packet")
	func busyGateRejectsBeforeBuildingForwardedPacket() async {
		let gate = MqttForwardGate()
		#expect(await gate.tryAcquire())

		var buildCount = 0
		let result = await MqttForwardAdmission.admit(gate: gate) {
			buildCount += 1
			return Data([0x01])
		}

		if case .admitted = result {
			Issue.record("Busy MQTT forward gate admitted queued work")
		}
		#expect(buildCount == 0)

		await gate.release()
	}

	@Test("Nil admitted work releases the gate")
	func nilAdmittedWorkReleasesGate() async throws {
		let gate = MqttForwardGate()
		let admission = await MqttForwardAdmission.admit(gate: gate) {
			Optional<Int>.none
		}

		var performedSend = false
		try await MqttForwardAdmission.complete(admission, gate: gate) { (_: Int) async throws in
			performedSend = true
		}

		#expect(!performedSend)
		let next = await MqttForwardAdmission.admit(gate: gate) {
			Optional.some(42)
		}
		if case .rejected = next {
			Issue.record("Gate stayed busy after admitted nil work")
		}
		try await MqttForwardAdmission.complete(next, gate: gate) { (_: Int) async throws in }
	}

	@Test("Successful work keeps the gate busy until completion")
	func successfulWorkKeepsGateBusyUntilCompletion() async throws {
		let gate = MqttForwardGate()
		let admission = await MqttForwardAdmission.admit(gate: gate) {
			Optional.some(1)
		}

		try await MqttForwardAdmission.complete(admission, gate: gate) { (_: Int) async throws in
			let whilePerforming = await MqttForwardAdmission.admit(gate: gate) {
				Optional.some(2)
			}
			if case .admitted = whilePerforming {
				Issue.record("Gate released before successful work completed")
			}
		}

		let afterCompletion = await MqttForwardAdmission.admit(gate: gate) {
			Optional.some(3)
		}
		if case .rejected = afterCompletion {
			Issue.record("Gate stayed busy after successful work completed")
		}
		try await MqttForwardAdmission.complete(afterCompletion, gate: gate) { (_: Int) async throws in }
	}

	@Test("Failed work releases the gate after completion")
	func failedWorkReleasesGateAfterCompletion() async {
		let gate = MqttForwardGate()
		let admission = await MqttForwardAdmission.admit(gate: gate) {
			Optional.some(1)
		}

		await #expect(throws: MqttForwardAdmissionTestError.disconnected) {
			try await MqttForwardAdmission.complete(admission, gate: gate) { (_: Int) async throws in
				let whilePerforming = await MqttForwardAdmission.admit(gate: gate) {
					Optional.some(2)
				}
				if case .admitted = whilePerforming {
					Issue.record("Gate released before failed work completed")
				}
				throw MqttForwardAdmissionTestError.disconnected
			}
		}

		let afterFailure = await MqttForwardAdmission.admit(gate: gate) {
			Optional.some(3)
		}
		if case .rejected = afterFailure {
			Issue.record("Gate stayed busy after failed work completed")
		}
		try? await MqttForwardAdmission.complete(afterFailure, gate: gate) { (_: Int) async throws in }
	}

	@Test("Busy rejection does not prevent a later admission after release")
	func busyRejectionAllowsLaterAdmissionAfterRelease() async throws {
		let gate = MqttForwardGate()
		let first = await MqttForwardAdmission.admit(gate: gate) {
			Optional.some(1)
		}

		let second = await MqttForwardAdmission.admit(gate: gate) {
			Optional.some(2)
		}
		if case .admitted = second {
			Issue.record("Busy gate admitted a second packet")
		}

		try await MqttForwardAdmission.complete(second, gate: gate) { (_: Int) async throws in }

		let stillBusy = await MqttForwardAdmission.admit(gate: gate) {
			Optional.some(3)
		}
		if case .admitted = stillBusy {
			Issue.record("Completing a rejected packet released the in-flight packet's gate")
		}

		try await MqttForwardAdmission.complete(first, gate: gate) { (_: Int) async throws in }

		let third = await MqttForwardAdmission.admit(gate: gate) {
			Optional.some(4)
		}
		if case .rejected = third {
			Issue.record("Gate rejected a later packet after release")
		}
		try await MqttForwardAdmission.complete(third, gate: gate) { (_: Int) async throws in }
	}
}
