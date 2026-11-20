//
//  CarPlayWidgetLink.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/20/26.
//

import Foundation

/// The CarPlay tab a widget's link opens. Tapping a widget on the CarPlay home screen opens the
/// CarPlay app with the widget's link; CarPlay only has Channels and Direct Messages, so a link
/// picks one of them, or none when there's nothing to show for it (the map, connecting).
enum CarPlayWidgetLink: Equatable {
	case channels
	case directMessages

	init?(url: URL) {
		guard url.scheme == "meshtastic",
			  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
		let section = components.path.split(separator: "/").first.map(String.init)
		let names = Set((components.queryItems ?? []).map(\.name))
		switch section {
		case "messages":
			if names.contains("userNum") {
				self = .directMessages
			} else if names.contains("channelId") {
				self = .channels
			} else {
				return nil
			}
		case "nodes" where names.contains("nodenum"):
			// A node's widget: the node is listed under Direct Messages.
			self = .directMessages
		default:
			return nil
		}
	}
}
