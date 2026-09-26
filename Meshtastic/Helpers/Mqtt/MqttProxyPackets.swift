//
//  MqttProxyPackets.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import CocoaMQTT
import Foundation
import MeshtasticProtobufs

/// The MQTT client proxy's packet handling, shared by the focused radio (`AccessoryManager`)
/// and each additional radio's bridge (feature 021, T100). Pure, so it's unit-testable without
/// a broker or a radio.
enum MqttProxyPackets {

	/// What to do with one message from the broker.
	enum Downlink: Equatable {
		/// Send `toRadio` to the radio. `zeroedHopLimit` is the hop limit it arrived with when
		/// it was clamped to 0, so it isn't re-broadcast over RF.
		case forward(ToRadio, zeroedHopLimit: UInt32?)
		/// A `/stat/` topic: nothing for the radio.
		case dropStat
		/// A packet the radio can't use (`MqttForwardFilter`).
		case dropNoPayload
	}

	/// Decides what a broker message becomes for the radio `myNodeNum` (0 when unknown).
	/// Unparseable bytes are forwarded unchanged, as before the filter existed.
	static func downlink(topic: String, payload: Data, retained: Bool, myNodeNum: UInt32) -> Downlink {
		if topic.contains("/stat/") {
			return .dropStat
		}
		let parsed = try? ServiceEnvelope(serializedBytes: payload)
		if let envelope = parsed {
			let myHex = myNodeNum == 0 ? "" : myNodeNum.toHex()
			if MqttForwardFilter.decide(envelope: envelope, myNodeHex: myHex) == .dropNoPayload {
				return .dropNoPayload
			}
		}

		// Clamp hop_limit to 0 on downlink ServiceEnvelopes before forwarding to the device.
		// Packets with hop_limit > 0 would be re-broadcast over RF, flooding the mesh with
		// traffic that arrived via MQTT. hop_start is preserved so receivers can still compute
		// how far the packet travelled.
		var forwardData = payload
		var zeroed: UInt32?
		if var envelope = parsed, envelope.hasPacket, envelope.packet.hopLimit > 0 {
			zeroed = envelope.packet.hopLimit
			envelope.packet.hopLimit = 0
			forwardData = (try? envelope.serializedData()) ?? payload
		}

		var proxyMessage = MqttClientProxyMessage()
		proxyMessage.topic = topic
		proxyMessage.data = forwardData
		proxyMessage.retained = retained
		var toRadio = ToRadio()
		toRadio.mqttClientProxyMessage = proxyMessage
		return .forward(toRadio, zeroedHopLimit: zeroed)
	}

	/// The broker message for a proxy message from the radio. Its payload is a oneof: binary
	/// `data` (service envelope, map report) or `text` (JSON, stat topics). Nil without one.
	static func uplink(_ message: MqttClientProxyMessage) -> CocoaMQTTMessage? {
		let payload: [UInt8]
		switch message.payloadVariant {
		case .data(let bytes):
			payload = [UInt8](bytes)
		case .text(let string):
			payload = [UInt8](string.utf8)
		case .none:
			return nil
		}
		return CocoaMQTTMessage(topic: message.topic, payload: payload, retained: message.retained)
	}
}
