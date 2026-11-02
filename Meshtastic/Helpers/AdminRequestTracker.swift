//
//  AdminRequestTracker.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Foundation
import MeshtasticProtobufs
import os

/// Remembers the admin requests this app sent, so an admin response is only applied when it
/// answers one of them. Any node on a shared channel can send a config, channel or metadata
/// "response" nobody asked for, and the firmware passes it up; without this check it would be
/// stored as that node's settings and sent back to it on the next Save.
enum AdminRequestTracker {

	/// Long enough for a reply over several hops on a slow preset.
	static let lifetime: TimeInterval = 600
	private static let limit = 256

	private struct Pending {
		let destination: UInt32
		let sentAt: Date
	}

	private static let pending = OSAllocatedUnfairLock(initialState: [UInt32: Pending]())

	/// Records an outgoing packet if it is an admin message that asks for a reply.
	static func recordIfAdminRequest(_ packet: MeshPacket, now: Date = .now) {
		guard packet.decoded.portnum == .adminApp, packet.decoded.wantResponse, packet.id != 0 else { return }
		pending.withLock { requests in
			requests = requests.filter { now.timeIntervalSince($0.value.sentAt) < lifetime }
			if requests.count >= limit, let oldest = requests.min(by: { $0.value.sentAt < $1.value.sentAt }) {
				requests.removeValue(forKey: oldest.key)
			}
			requests[packet.id] = Pending(destination: packet.to, sentAt: now)
		}
	}

	/// Whether `packet` answers a request this app sent to the node it came from. A match is used
	/// up, so the same response cannot be replayed. A response from any node other than the
	/// connected one must have arrived PKI encrypted; the legacy admin channel is not supported.
	static func consumeResponse(_ packet: MeshPacket, connectedNodeNum: Int64?, now: Date = .now) -> Bool {
		let requestID = packet.decoded.requestID
		guard requestID != 0, let connectedNodeNum, Int64(packet.to) == connectedNodeNum else { return false }
		if Int64(packet.from) != connectedNodeNum && !packet.pkiEncrypted { return false }
		return pending.withLock { requests in
			guard let request = requests[requestID],
				  request.destination == packet.from,
				  now.timeIntervalSince(request.sentAt) < lifetime else { return false }
			requests.removeValue(forKey: requestID)
			return true
		}
	}
}
