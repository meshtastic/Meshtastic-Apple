//
//  MqttForwardFilter.swift
//  Meshtastic
//
//  Decides whether a downlink MQTT ServiceEnvelope received from the broker is
//  worth forwarding to the connected node over BLE. In client-proxy mode the
//  public broker delivers a large, continuous stream of packets the node cannot
//  use — most visibly payload-less packet-header stubs on LongFast — and the app
//  is the cheapest place to drop them (it already holds the bytes). Pure and
//  side-effect free so the decision can be exhaustively unit-tested without an
//  AccessoryManager, SwiftData, or the CocoaMQTT delegate thread.
//

import Foundation
import MeshtasticProtobufs

/// Why a downlink MQTT packet was (or was not) forwarded to the node.
enum MqttForwardDecision: Equatable {
	/// Forward the packet to the device (the default; fail-open outcome).
	case forward
	/// Drop: the inner MeshPacket carries no payload, so there is nothing the
	/// node could ever act on (Tier 1).
	case dropNoPayload
}

/// Pure decision for the MQTT client-proxy receive path. Fails open: it only
/// returns `.dropNoPayload` for a packet it can positively prove is undeliverable;
/// anything uncertain forwards unchanged, exactly as before the filter existed.
enum MqttForwardFilter {

	/// - Parameters:
	///   - envelope:  the already-parsed ServiceEnvelope (unparseable bytes are
	///                forwarded at the call site, before this runs).
	///   - myNodeHex: the connected node's hex id (e.g. "!433e2700"); pass "" when unknown.
	static func decide(envelope: ServiceEnvelope, myNodeHex: String) -> MqttForwardDecision {
		// Guard: our own echoed-back packet. The node uses these as implicit ACKs
		// to stop retransmissions, so they must never be dropped. (They carry a
		// payload and would pass Tier 1 anyway; the explicit guard keeps a future
		// change from breaking ACKs.)
		if !myNodeHex.isEmpty,
		   envelope.gatewayID.caseInsensitiveCompare(myNodeHex) == .orderedSame {
			return .forward
		}

		// Guard: the node intentionally accepts PKC direct messages on the PKI
		// topic without decrypting them first. Never filter PKI traffic.
		if envelope.channelID == "PKI" {
			return .forward
		}

		// No packet at all → nothing we can prove undeliverable; fail open.
		// (A packet-less envelope's `.packet` is a default MeshPacket with a nil
		// payload variant, which must NOT be treated as a Tier 1 drop.)
		guard envelope.hasPacket else {
			return .forward
		}

		// Tier 1: a MeshPacket with neither `decoded` nor `encrypted` set carries
		// nothing the node can use. No legitimate Meshtastic packet is payload-less.
		if envelope.packet.payloadVariant == nil {
			return .dropNoPayload
		}

		return .forward
	}
}
