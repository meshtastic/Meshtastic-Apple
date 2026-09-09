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
/// A radio wearing a shield badge rather than a bare shield, because what was verified is *who this
/// node says it is*. A plain checkmark shield reads as "secure" generally, which is the lock's job.
///
/// Held in one place so the node list rows, the node list help and node detail cannot drift apart —
/// they show the same fact and are meant to look identical.
enum SignedNodeIcon {
	/// A custom symbol in the asset catalog, so it ships inside the app bundle and there is no
	/// deployment-target question the way there is for an SF Symbol.
	static let symbolName = "custom.mesh.radio.badge.shield.checkmark"

	/// Asset catalog symbols load through `Image(_:)`. `Image(systemName:)` finds nothing for them
	/// and SwiftUI draws nothing at all rather than failing, so a caller reaching for it by habit
	/// would get a silently blank row. Vended as a view so no caller has to remember which it is.
	static var image: Image { Image(symbolName) }
}
