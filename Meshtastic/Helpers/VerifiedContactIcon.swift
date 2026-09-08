//
//  VerifiedContactIcon.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/8/26.
//

import SwiftUI

/// The glyph for a contact whose key you verified in person, by exchanging contact QR codes.
///
/// The filled person badge, which is the strongest trust the app shows. Distinct from
/// `SignedNodeIcon`, the radio badge, which is the weaker fact that a radio vouched for a node
/// over the mesh.
///
/// Held in one place so the node list, node detail, the add-contact sheet and the help legend
/// cannot drift apart — they show the same fact and are meant to look identical.
enum VerifiedContactIcon {
	static let symbolName = "person.badge.shield.checkmark.fill"

	static var image: Image { Image(systemName: symbolName) }
}
