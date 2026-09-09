//
//  AutoFavoriteRuleTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Testing
import Foundation
@testable import Meshtastic

/// Covers `AutoFavoriteRule` — whether sending a direct message pins the destination in the
/// radio's node db. Client base is excluded at both ends.
@Suite("AutoFavoriteRule")
struct AutoFavoriteRuleTests {

	private let client = Int32(DeviceRoles.client.rawValue)
	private let clientBase = Int32(DeviceRoles.clientBase.rawValue)

	@Test("favorites an ordinary node from an ordinary node")
	func favoritesOrdinaryNode() {
		#expect(AutoFavoriteRule.shouldFavorite(destinationRole: client, connectedRole: .client, isAlreadyFavorite: false))
	}

	@Test("never favorites when the connected node is a client base")
	func neverFavoritesFromClientBase() {
		#expect(!AutoFavoriteRule.shouldFavorite(destinationRole: client, connectedRole: .clientBase, isAlreadyFavorite: false))
	}

	@Test("never favorites a client base destination")
	func neverFavoritesClientBaseDestination() {
		#expect(!AutoFavoriteRule.shouldFavorite(destinationRole: clientBase, connectedRole: .client, isAlreadyFavorite: false))
	}

	@Test("never favorites client base to client base")
	func neverFavoritesClientBaseBothEnds() {
		#expect(!AutoFavoriteRule.shouldFavorite(destinationRole: clientBase, connectedRole: .clientBase, isAlreadyFavorite: false))
	}

	@Test("skips a node that is already a favorite")
	func skipsExistingFavorite() {
		// Nothing to send, and re-sending would put an admin message on the mesh for every message.
		#expect(!AutoFavoriteRule.shouldFavorite(destinationRole: client, connectedRole: .client, isAlreadyFavorite: true))
	}

	@Test("favorites when the destination role is unknown")
	func favoritesUnknownDestinationRole() {
		// A node we have no device config for is treated as an ordinary contact.
		#expect(AutoFavoriteRule.shouldFavorite(destinationRole: nil, connectedRole: .client, isAlreadyFavorite: false))
	}

	@Test("favorites when the connected role is unknown")
	func favoritesUnknownConnectedRole() {
		#expect(AutoFavoriteRule.shouldFavorite(destinationRole: client, connectedRole: nil, isAlreadyFavorite: false))
	}

	@Test("router and repeater destinations are still favorited")
	func favoritesInfrastructureThatIsNotClientBase() {
		// Only client base is carved out; the rule must not quietly widen to other roles.
		#expect(AutoFavoriteRule.shouldFavorite(destinationRole: Int32(DeviceRoles.router.rawValue), connectedRole: .client, isAlreadyFavorite: false))
		#expect(AutoFavoriteRule.shouldFavorite(destinationRole: Int32(DeviceRoles.repeater.rawValue), connectedRole: .client, isAlreadyFavorite: false))
	}
}
