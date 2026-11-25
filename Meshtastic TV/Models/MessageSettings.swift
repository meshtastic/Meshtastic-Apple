//
//  MessageSettings.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 11/24/26.
//
//  Which incoming text messages the map shows. Stored in @AppStorage so Settings
//  and MapScreen share them. Channels are stored as the set to hide, so a channel
//  added on the radio later shows by default.
//

import CoreLocation
import Foundation

enum MessageSettings {
	static let enabledKey = "tv.messages.enabled"
	static let directMessagesKey = "tv.messages.directMessages"
	static let hiddenChannelsKey = "tv.messages.hiddenChannels"

	/// Decodes the stored hidden channel indexes ("1,3").
	static func hiddenChannels(from raw: String) -> Set<Int> {
		Set(raw.split(separator: ",").compactMap { Int($0) })
	}

	static func encode(_ hidden: Set<Int>) -> String {
		hidden.sorted().map(String.init).joined(separator: ",")
	}

	static func shouldShow(
		_ message: MeshClient.TextMessage,
		directMessages: Bool,
		hiddenChannels: Set<Int>
	) -> Bool {
		message.isDirect ? directMessages : !hiddenChannels.contains(message.channelIndex)
	}
}

/// A message waiting for, or showing in, a bubble on the map.
struct MapMessage: Identifiable, Equatable {
	let id: UUID
	let num: UInt32
	let senderName: String
	let text: String
	let coordinate: CLLocationCoordinate2D

	static func == (lhs: MapMessage, rhs: MapMessage) -> Bool { lhs.id == rhs.id }
}
