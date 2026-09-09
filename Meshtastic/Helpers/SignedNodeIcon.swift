//
//  SignedNodeIcon.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import SwiftUI

/// The glyph for a signed node — a node whose NodeInfo broadcast carried an XEdDSA signature the
/// radio verified.
///
/// A radio carrying a shield badge, because what the radio vouched for is the node itself. The
/// person badge means something different and stronger: a contact you verified in person.
///
/// Held in one place so the node list, node detail and the filter cannot drift apart — they show
/// the same fact and are meant to look identical.
enum SignedNodeIcon {
	/// A custom symbol from the asset catalog, so it must be loaded by name rather than through
	/// `systemName`, which only resolves symbols the OS ships. Use `image` wherever SwiftUI needs
	/// the glyph directly.
	static let symbolName = "radio.badge.shield.checkmark"

	static var image: Image { Image(symbolName) }
}
