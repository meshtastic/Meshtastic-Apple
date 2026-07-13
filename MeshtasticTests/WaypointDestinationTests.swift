//
//  WaypointDestinationTests.swift
//  MeshtasticTests
//

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("waypointDestination contact derivation")
struct WaypointDestinationDerivationTests {

	@Test("A broadcast packet resolves to its channel")
	func broadcastResolvesToChannel() {
		var packet = MeshPacket()
		packet.to = Constants.maximumNodeNum
		packet.from = 111
		packet.channel = 2

		let destination = waypointDestination(packet: packet, myNodeNum: 111)
		#expect(destination == .channel(2))
	}

	@Test("A DM we sent resolves to its recipient (packet.to)")
	func sentDMResolvesToRecipient() {
		var packet = MeshPacket()
		packet.from = 111
		packet.to = 222

		let destination = waypointDestination(packet: packet, myNodeNum: 111)
		#expect(destination == .user(222))
	}

	@Test(
		"""
		A DM sent TO us by someone else resolves to the sender (packet.from), not ourselves — otherwise a \
		follow-up would self-address back to us instead of reaching the original sender
		"""
	)
	func receivedDMResolvesToSender() {
		var packet = MeshPacket()
		packet.from = 333
		packet.to = 111 // addressed to us

		let destination = waypointDestination(packet: packet, myNodeNum: 111)
		#expect(destination == .user(333))
	}

	@Test("Unknown local node number still classifies a DM as belonging to the sender")
	func unknownLocalNodeFallsBackToSender() {
		var packet = MeshPacket()
		packet.from = 333
		packet.to = 111

		let destination = waypointDestination(packet: packet, myNodeNum: nil)
		#expect(destination == .user(333))
	}
}

@Suite("WaypointEntity.destination round trip")
struct WaypointEntityDestinationTests {

	@Test("Defaults to the primary channel broadcast")
	func defaultsToBroadcastPrimary() {
		let waypoint = WaypointEntity()
		#expect(waypoint.destination == .channel(0))
	}

	@Test("Setting a channel destination clears any DM node")
	func settingChannelClearsUser() {
		let waypoint = WaypointEntity()
		waypoint.destination = .user(555)
		waypoint.destination = .channel(3)
		#expect(waypoint.destination == .channel(3))
		#expect(waypoint.destinationNodeNum == 0)
	}

	@Test("Setting a DM destination clears any channel")
	func settingUserClearsChannel() {
		let waypoint = WaypointEntity()
		waypoint.destination = .channel(3)
		waypoint.destination = .user(555)
		#expect(waypoint.destination == .user(555))
		#expect(waypoint.destinationChannel == 0)
	}

	@Test("Re-editing an existing waypoint preserves its original DM recipient rather than resetting to broadcast")
	func editingPreservesOriginalDMDestination() {
		let waypoint = WaypointEntity()
		waypoint.destination = .user(42)

		// Simulate re-opening the editor: the destination read back must still be the DM, not broadcast.
		#expect(waypoint.destination == .user(42))
	}
}

@Suite("Recipient label fallbacks")
struct WaypointRecipientLabelTests {

	@Test("A node with a long name uses it")
	func longNameWins() {
		let node = NodeInfoEntity()
		node.num = 123
		let user = UserEntity()
		user.longName = "Field Radio"
		user.shortName = "FLD"
		node.user = user

		#expect(waypointNodeLabel(node) == "Field Radio")
	}

	@Test("A blank long name falls through to the short name")
	func blankLongNameFallsThroughToShortName() {
		let node = NodeInfoEntity()
		node.num = 123
		let user = UserEntity()
		user.longName = ""
		user.shortName = "FLD"
		node.user = user

		#expect(waypointNodeLabel(node) == "FLD")
	}

	@Test("Blank long and short names fall through to a node-id-derived label, never blank or 'Broadcast'")
	func blankNamesFallThroughToNodeId() {
		let node = NodeInfoEntity()
		node.num = 123
		let user = UserEntity()
		user.longName = ""
		user.shortName = ""
		node.user = user

		let label = waypointNodeLabel(node)
		#expect(!label.isEmpty)
		#expect(label == Int64(123).toHex())
	}

	@Test("No user record at all still falls through to a node-id-derived label")
	func noUserFallsThroughToNodeId() {
		let node = NodeInfoEntity()
		node.num = 456

		#expect(waypointNodeLabel(node) == Int64(456).toHex())
	}

	@Test("A configured channel name is used verbatim")
	func configuredChannelNameWins() {
		let channel = ChannelEntity()
		channel.index = 0
		channel.name = "LongFast"

		#expect(waypointChannelLabel(index: 0, channels: [channel], node: nil) == "LongFast")
	}

	@Test("An unnamed secondary channel falls back to 'Channel N'")
	func unnamedSecondaryChannelFallsBackToIndex() {
		#expect(waypointChannelLabel(index: 3, channels: [], node: nil) == "Channel 3")
	}

	@Test("No channel info at all (e.g. disconnected) falls back to a generic Broadcast label")
	func disconnectedFallsBackToGenericBroadcast() {
		#expect(waypointChannelLabel(index: 0, channels: [], node: nil) == "Broadcast".localized)
	}

	@Test("A node with a non-preset LoRa config falls back to 'Custom'")
	func nonPresetLoRaConfigFallsBackToCustom() {
		let node = NodeInfoEntity()
		node.num = 123
		let loRaConfig = LoRaConfigEntity()
		loRaConfig.usePreset = false
		node.loRaConfig = loRaConfig

		#expect(waypointChannelLabel(index: 0, channels: [], node: node) == "Custom".localized)
	}

	@Test("An unresolvable modemPreset rawValue falls back to 'LongFast', matching the Channels settings screen")
	func unresolvableModemPresetFallsBackToLongFast() {
		let node = NodeInfoEntity()
		node.num = 123
		let loRaConfig = LoRaConfigEntity()
		loRaConfig.usePreset = true
		loRaConfig.modemPreset = 99 // no ModemPresets case has this rawValue
		node.loRaConfig = loRaConfig

		#expect(waypointChannelLabel(index: 0, channels: [], node: node) == "LongFast")
	}
}

@Suite("Recipient picker filtering")
struct WaypointRecipientPickerFilteringTests {

	@Test("The primary channel is always listed even if it hasn't synced into channels yet")
	func primaryChannelAlwaysListed() {
		let secondary = ChannelEntity()
		secondary.index = 1
		secondary.name = "Secondary"

		#expect(waypointChannelIndexes(channels: [secondary]) == [0, 1])
	}

	@Test("Channel indexes are deduped and sorted")
	func channelIndexesDedupedAndSorted() {
		let primary = ChannelEntity()
		primary.index = 0
		let secondary = ChannelEntity()
		secondary.index = 2

		#expect(waypointChannelIndexes(channels: [secondary, primary]) == [0, 2])
	}

	@Test("The connected device's own node never appears in the DM candidate list")
	func ownNodeExcludedFromDMList() {
		let me = NodeInfoEntity()
		me.num = 111
		let other = NodeInfoEntity()
		other.num = 222

		let filtered = waypointFilterNodes([me, other], excluding: 111, matching: "")
		#expect(filtered.map(\.num) == [222])
	}

	@Test("An ignored node is excluded from the DM candidate list")
	func ignoredNodeExcluded() {
		let ignored = NodeInfoEntity()
		ignored.num = 222
		ignored.ignored = true
		let visible = NodeInfoEntity()
		visible.num = 333

		let filtered = waypointFilterNodes([ignored, visible], excluding: nil, matching: "")
		#expect(filtered.map(\.num) == [333])
	}

	@Test("A name filter narrows the node list case-insensitively")
	func filterNarrowsByName() {
		let match = NodeInfoEntity()
		match.num = 111
		let matchUser = UserEntity()
		matchUser.longName = "Field Radio"
		match.user = matchUser

		let nonMatch = NodeInfoEntity()
		nonMatch.num = 222
		let nonMatchUser = UserEntity()
		nonMatchUser.longName = "Base Station"
		nonMatch.user = nonMatchUser

		let filtered = waypointFilterNodes([match, nonMatch], excluding: nil, matching: "field")
		#expect(filtered.map(\.num) == [111])
	}
}
