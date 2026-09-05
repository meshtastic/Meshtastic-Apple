//
//  SignedNodeIcon.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Foundation

/// The glyph for a signed node — a node whose NodeInfo broadcast carried an XEdDSA signature the
/// radio verified.
///
/// A person badge rather than a bare shield, because what was verified is *who this node says it
/// is*. A plain checkmark shield reads as "secure" generally, which is the lock's job.
///
/// Held in one place so the node list rows and node detail cannot drift apart — they show the same
/// fact and are meant to look identical.
enum SignedNodeIcon {
	/// Introduced in iOS 16.0 per the SF Symbols catalog, so it resolves on the 17.5 deployment
	/// target. SwiftUI renders nothing at all for a symbol the running OS does not have, so a
	/// too-new name would leave the row silently blank rather than fail the build.
	static let symbolName = "person.badge.shield.checkmark.fill"
}
