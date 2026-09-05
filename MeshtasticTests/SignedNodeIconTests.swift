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

/// The signed-node icon says the radio verified who this node claims to be. SwiftUI renders nothing
/// at all for a name that does not exist, so a typo or a symbol that needs a newer OS than the
/// deployment target would silently leave the row blank rather than fail a build.
@Suite("Signed node icon")
struct SignedNodeIconTests {

	private let signedNodeSymbol = "person.badge.shield.checkmark.fill"

	@Test("the signed node symbol resolves on this deployment target")
	func symbolResolves() throws {
		#if canImport(UIKit)
		#expect(UIImage(systemName: signedNodeSymbol) != nil)
		#endif
	}

	@Test("the node list and node detail use the same symbol")
	func symbolIsConsistentAcrossViews() throws {
		// The rows carry comments saying they mirror the Node Detail row, so a change to one that
		// misses the others would leave the same fact drawn two different ways.
		let sources = [
			"Meshtastic/Views/Nodes/Helpers/NodeListItem.swift",
			"Meshtastic/Views/Nodes/Helpers/NodeListItemCompact.swift",
			"Meshtastic/Views/Nodes/Helpers/NodeDetail.swift"
		]

		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()

		for source in sources {
			let contents = try String(contentsOf: root.appendingPathComponent(source), encoding: .utf8)
			#expect(contents.contains(signedNodeSymbol), "\(source) does not use the signed node symbol")
		}
	}
}
