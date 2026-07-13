//
//  WaypointDestination.swift
//  Meshtastic
//

import Foundation
import MeshtasticProtobufs

/// Where a waypoint is addressed: broadcast on a channel (including the primary channel, index 0), or a
/// private direct message to a specific node.
enum WaypointDestination: Equatable {
	case channel(Int32)
	case user(Int64)

	static let broadcastPrimary = WaypointDestination.channel(0)

	var channelNum: Int32 {
		switch self {
		case let .channel(index): return index
		case .user: return 0
		}
	}

	var userNum: Int64 {
		switch self {
		case .channel: return 0
		case let .user(num): return num
		}
	}
}

extension MeshPacket {
	/// A packet addressed to the mesh-wide broadcast address rather than a single node.
	var isBroadcast: Bool { to == Constants.maximumNodeNum }
}

/// The contact (channel or node) a waypoint packet was exchanged on. Used both when we send a waypoint and
/// when we receive one, so re-editing or deleting an existing waypoint always routes back to the same
/// conversation it was created in, instead of drifting to broadcast.
///
/// `packet.to` is only trustworthy as "the recipient" when we sent the packet ourselves or it was a
/// broadcast. For a waypoint DM'd *to us* by someone else, `packet.to` is our own node number — reading it
/// unconditionally would self-address any follow-up (re-editing, "delete for everyone") back to ourselves
/// instead of the original sender, so the update would silently never reach them. When that's the case, fall
/// back to `packet.from`, the sender.
func waypointDestination(packet: MeshPacket, myNodeNum: UInt32?) -> WaypointDestination {
	if packet.isBroadcast {
		return .channel(Int32(truncatingIfNeeded: packet.channel))
	}
	let contact = (myNodeNum != nil && packet.from == myNodeNum) ? packet.to : packet.from
	return .user(Int64(contact))
}
