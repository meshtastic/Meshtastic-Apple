//
//  UnheardNodesPromptCopyTests.swift
//  MeshtasticTests
//

import Testing
@testable import Meshtastic

@Suite("Unheard nodes prompt copy")
struct UnheardNodesPromptCopyTests {

	@Test("compact review row names the affected nodes")
	func describesReviewRowClearly() {
		#expect(UnheardNodesPromptCopy.headline(nodeCount: 1) == "1 node needs review")
		#expect(UnheardNodesPromptCopy.headline(nodeCount: 4) == "4 nodes need review")
		#expect(UnheardNodesPromptCopy.reviewTitle == "Nodes Needing Review")
		#expect(UnheardNodesPromptCopy.reviewMessage == "These nodes haven’t been heard since the radio settings changed. Favorite nodes and this radio are kept.")
	}

	@Test("destructive confirmation names the affected nodes")
	func describesCleanupClearly() {
		#expect(UnheardNodesPromptCopy.confirmationTitle(nodeCount: 1) == "Remove 1 Node?")
		#expect(UnheardNodesPromptCopy.confirmationTitle(nodeCount: 4) == "Remove 4 Nodes?")
		#expect(UnheardNodesPromptCopy.confirmationMessage == "Remove these nodes from this app and the connected radio? Nodes heard again later will reappear.")
		#expect(UnheardNodesPromptCopy.removeAction == "Remove Nodes")
	}
}
