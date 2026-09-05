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

	@Test("the signed node symbol is the person badge, not a bare shield")
	func symbolIsThePersonBadge() {
		// The three views that draw this all read the constant, so they cannot drift from each other
		// — only from intent, which is what this pins. `checkmark.shield.fill` reads as "secure"
		// generally and is what the message signature badges still use.
		#expect(SignedNodeIcon.symbolName == "person.badge.shield.checkmark.fill")
	}

	@Test("the signed node symbol resolves at runtime")
	func symbolResolves() {
		// A smoke test for a typo, and nothing more: UIImage(systemName:) asks the *running* OS, so
		// passing here does not prove the symbol exists on the 17.5 deployment target. What settles
		// that is the SF Symbols catalog, which puts this symbol at iOS 16.0 — see SignedNodeIcon.
		#if canImport(UIKit)
		#expect(UIImage(systemName: SignedNodeIcon.symbolName) != nil)
		#endif
	}
}
