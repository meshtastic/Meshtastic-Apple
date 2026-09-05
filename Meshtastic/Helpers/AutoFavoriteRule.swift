//
//  AutoFavoriteRule.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Foundation

/// Decides whether sending a direct message should favorite the node it is addressed to.
///
/// Favoriting pins the node in the radio's node db so it does not age out from under an ongoing
/// conversation. Client base is excluded at both ends: a client base should only favorite nodes its
/// operator controls, and a client base is infrastructure rather than a contact worth pinning.
enum AutoFavoriteRule {

	static func shouldFavorite(
		destinationRole: Int32?,
		connectedRole: DeviceRoles?,
		isAlreadyFavorite: Bool
	) -> Bool {
		// Already pinned, so there is nothing to send.
		if isAlreadyFavorite { return false }
		// Never auto favorite from a client base, whatever it is messaging.
		if connectedRole == .clientBase { return false }
		// Never auto favorite a client base, whoever is messaging it.
		if let destinationRole, Int(destinationRole) == DeviceRoles.clientBase.rawValue { return false }
		return true
	}
}
