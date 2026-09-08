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

	@Test("the signed node symbol is the radio badge, not the person badge")
	func symbolIsTheRadioBadge() {
		// The list rows, node detail, the filter and the help legend all read this constant, so they
		// cannot drift from each other — only from intent, which is what this pins. The person badge
		// means something different and stronger: a contact verified face to face.
		#expect(SignedNodeIcon.symbolName == "radio.badge.shield.checkmark")
	}

	@Test("the signed node symbol loads from the asset catalog")
	func symbolLoads() {
		// This is a custom symbol, so it is loaded by name rather than through systemName. It is
		// worth asserting: a symbol template only fills, so artwork drawn with strokes compiles into
		// the catalog and then draws nothing at all — the row goes silently blank.
		#if canImport(UIKit)
		let image = UIImage(named: SignedNodeIcon.symbolName)
		#expect(image != nil)
		#expect(image?.isSymbolImage == true)
		// A glyph that carries no fill reports no size, which is what a stroked template does.
		#expect((image?.size.width ?? 0) > 1)
		#expect((image?.size.height ?? 0) > 1)
		#expect(UIImage(systemName: SignedNodeIcon.symbolName) == nil, "not a system symbol")
		#endif
	}
}
