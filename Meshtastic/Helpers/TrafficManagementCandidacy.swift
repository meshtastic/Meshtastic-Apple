//
//  TrafficManagementCandidacy.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/7/26.
//

import Foundation

/// Whether this radio is placed where the Traffic Management module earns its keep.
///
/// The module pays off on a node that reaches many others in a single transmission — its author's
/// guidance is 50 or more, ideally around 200. At that density, cutting hop counts on the chattiest
/// packets removes the retransmission storm that follows each broadcast. A node with a handful of
/// direct neighbors has nothing to police.
///
/// The measurement is the nodes this radio has heard directly: zero hops, over RF rather than MQTT,
/// recently enough to still be there. It reflects what this phone's store has recorded, so a phone
/// that connects rarely may undercount.
enum TrafficManagementCandidacy {

	/// The author's floor: below this, one transmission does not reach enough of the mesh.
	static let goodNeighborCount = 50
	/// The author's sweet spot.
	static let strongNeighborCount = 200

	enum Tier {
		case strong
		case good
		case limited
	}

	static func tier(directNeighborCount: Int) -> Tier {
		if directNeighborCount >= strongNeighborCount { return .strong }
		if directNeighborCount >= goodNeighborCount { return .good }
		return .limited
	}

	static func summary(directNeighborCount count: Int) -> String {
		switch tier(directNeighborCount: count) {
		case .strong:
			return String(localized: "This node hears \(count) nodes directly — a strong fit. One transmission from here reaches enough of the mesh for traffic management to cut the retransmission storm that follows.")
		case .good:
			return String(localized: "This node hears \(count) nodes directly — a good fit. Traffic management works best from around 200 direct neighbors, but from 50 it already has traffic worth policing.")
		case .limited:
			return String(localized: "This node hears \(count) nodes directly in the last two hours. Traffic management is built for well-placed nodes that reach 50 or more in a single transmission; it will have little effect here.")
		}
	}
}
