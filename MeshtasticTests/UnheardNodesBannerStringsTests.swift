//
//  UnheardNodesBannerStringsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//

import Testing
@testable import Meshtastic

/// The banner's two counted strings used automatic grammar agreement, which only inflects
/// when the string catalog has a value to compile. Their catalog entries had none, so the
/// banner showed the markup verbatim. These resolve the same strings the view builds, so a
/// catalog entry going missing again fails here rather than on someone's screen.
@Suite("Unheard nodes banner strings")
struct UnheardNodesBannerStringsTests {

	private func headline(_ count: Int) -> String {
		String(localized: "\(count) nodes not heard since you changed settings")
	}

	private func confirmation(_ count: Int) -> String {
		String(localized: "Remove \(count) nodes?", comment: "Confirmation title for removing nodes not heard since the settings changed")
	}

	@Test("one node reads as one node")
	func singular() {
		#expect(headline(1).hasPrefix("1 node "))
		#expect(confirmation(1) == "Remove 1 node?")
	}

	@Test("more than one reads as nodes")
	func plural() {
		#expect(headline(4).hasPrefix("4 nodes "))
		#expect(confirmation(4) == "Remove 4 nodes?")
		#expect(confirmation(0) == "Remove 0 nodes?")
	}

	@Test("no grammar markup reaches the screen")
	func noMarkupLeaks() {
		for count in [0, 1, 2, 12] {
			for text in [headline(count), confirmation(count)] {
				#expect(!text.contains("^["), "\(count): markup leaked")
				#expect(!text.contains("inflect"), "\(count): markup leaked")
			}
		}
	}
}
