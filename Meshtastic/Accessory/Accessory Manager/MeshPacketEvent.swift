//
//  MeshPacketEvent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import Foundation
import MeshtasticProtobufs

/// One packet the connected radio just heard, reduced to what a live view needs. Published by
/// `AccessoryManager.packetEvents` for packets heard now: not the stored packets the radio replays
/// after a node database download (those are marked LoRa but carry no RSSI), and not the ACKs the
/// radio generates itself.
struct MeshPacketEvent: Sendable, Equatable {
	let packetID: UInt32
	let from: Int64
	let to: Int64
	let channel: Int32
	let portNum: PortNum
	let rxSnr: Float
	let rxRssi: Int32
	/// Hops the packet traveled before this radio heard it, when the sender reported a hop start.
	let hopsTraveled: Int?
	let viaMqtt: Bool
	/// App time of arrival; the radio's rxTime can be 0 or from an unset clock.
	let receivedAt: Date

	static let broadcastNum: Int64 = 0xFFFF_FFFF

	/// Nil for a packet that isn't a live reception.
	init?(packet: MeshPacket, receivedAt: Date = Date()) {
		guard packet.from != 0 else { return nil }
		// MQTT receptions have no RSSI but are live; replayed packets are marked LoRa without one.
		guard packet.hasRxRssi || packet.viaMqtt else { return nil }
		let portNum: PortNum = if case let .decoded(data) = packet.payloadVariant { data.portnum } else { .unknownApp }
		// A routing packet with no receive time is an ACK the radio made itself.
		guard !(portNum == .routingApp && packet.rxTime == 0) else { return nil }
		packetID = packet.id
		from = Int64(packet.from)
		to = Int64(packet.to)
		channel = Int32(packet.channel)
		self.portNum = portNum
		rxSnr = packet.rxSnr
		rxRssi = packet.rxRssi
		hopsTraveled = packet.hopStart > 0 && packet.hopStart >= packet.hopLimit ? Int(packet.hopStart - packet.hopLimit) : nil
		viaMqtt = packet.viaMqtt
		self.receivedAt = receivedAt
	}

	var isBroadcast: Bool { to == Self.broadcastNum }
}
