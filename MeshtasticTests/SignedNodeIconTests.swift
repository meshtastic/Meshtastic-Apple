//
//  SignedNodeIconTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import Meshtastic

/// The signed-node icon says the radio verified who this node claims to be.
@Suite("Signed node icon")
struct SignedNodeIconTests {

	@Test("the signed node symbol is the mesh radio wearing a shield badge")
	func symbolIsTheBadgedRadio() {
		// The node list rows, the node list help and node detail all read the constant, so they
		// cannot drift from each other — only from intent, which is what this pins.
		// `checkmark.shield.fill` reads as "secure" generally and is what message signature badges
		// still use; this one has to say *whose* identity was verified.
		#expect(SignedNodeIcon.symbolName == "custom.mesh.radio.badge.shield.checkmark")
	}

	@Test("the signed node symbol is in the asset catalog")
	func symbolResolves() {
		// A custom symbol, not an SF Symbol, so it ships in the app bundle and `UIImage(named:)` is
		// what finds it — `UIImage(systemName:)` returns nil for these. Catches a renamed or
		// missing symbolset, which SwiftUI would otherwise draw as nothing at all.
		#if canImport(UIKit)
		#expect(UIImage(named: SignedNodeIcon.symbolName, in: .main, with: nil) != nil)
		#endif
	}
}
