//
//  StatusMessageDisplayTests.swift
//  MeshtasticTests
//
//  Coverage for `NodeInfoEntity.statusMessageDisplay`, the shared resolver the node list
//  cards and node detail use to decide what (if anything) to render for a node's status.
//  It must:
//    - prefer the live broadcast value (`nodeStatus`, NODE_STATUS_APP) over the configured
//      value (`statusMessageConfig`), falling back to the configured value otherwise;
//    - return nil for empty / unset / whitespace-only inputs so callers omit the row
//      entirely (the design spec forbids a placeholder); and
//    - treat all-invisible strings (zero-width / format characters) as empty so an untrusted
//      broadcast can't render a blank icon-only row.
//

import Foundation
import Testing

@testable import Meshtastic

@MainActor
@Suite("NodeInfoEntity.statusMessageDisplay")
struct StatusMessageDisplayTests {

	private func makeNode(broadcast: String? = nil, configured: String? = nil) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.nodeStatus = broadcast
		if let configured {
			let config = StatusMessageConfigEntity()
			config.nodeStatus = configured
			node.statusMessageConfig = config
		}
		return node
	}

	// MARK: - Presence

	@Test func returnsBroadcastStatusWhenPresent() {
		#expect(makeNode(broadcast: "Ready to mesh").statusMessageDisplay == "Ready to mesh")
	}

	@Test func returnsConfiguredStatusWhenNoBroadcast() {
		#expect(makeNode(broadcast: nil, configured: "Battery Low").statusMessageDisplay == "Battery Low")
	}

	@Test func broadcastTakesPrecedenceOverConfigured() {
		#expect(makeNode(broadcast: "Live", configured: "Configured").statusMessageDisplay == "Live")
	}

	// MARK: - Omission (empty / unset / whitespace)

	@Test func returnsNilWhenBothUnset() {
		#expect(makeNode().statusMessageDisplay == nil)
	}

	@Test func returnsNilForEmptyBroadcastAndNoConfig() {
		#expect(makeNode(broadcast: "").statusMessageDisplay == nil)
	}

	@Test func returnsNilForWhitespaceOnly() {
		#expect(makeNode(broadcast: "   \n\t ").statusMessageDisplay == nil)
	}

	@Test func trimsSurroundingWhitespace() {
		#expect(makeNode(broadcast: "  Going to the farm  ").statusMessageDisplay == "Going to the farm")
	}

	// MARK: - Fallback when broadcast is blank/invisible

	@Test func whitespaceOnlyBroadcastFallsBackToConfigured() {
		#expect(makeNode(broadcast: "   ", configured: "Configured").statusMessageDisplay == "Configured")
	}

	@Test func invisibleOnlyBroadcastFallsBackToConfigured() {
		// Zero-width space + word joiner — non-empty by `isEmpty` but renders nothing.
		#expect(makeNode(broadcast: "\u{200B}\u{2060}", configured: "Configured").statusMessageDisplay == "Configured")
	}

	// MARK: - Invisible characters treated as empty

	@Test func returnsNilForZeroWidthOnly() {
		#expect(makeNode(broadcast: "\u{200B}\u{FEFF}\u{200E}").statusMessageDisplay == nil)
	}

	@Test func returnsNilForWhitespaceOnlyConfigured() {
		#expect(makeNode(broadcast: nil, configured: "  ").statusMessageDisplay == nil)
	}

	@Test func keepsVisibleTextThatContainsInvisibleCharacters() {
		// A real status that merely includes a zero-width joiner (e.g. an emoji sequence)
		// must still render.
		#expect(makeNode(broadcast: "Hi\u{200D}!").statusMessageDisplay == "Hi\u{200D}!")
	}
}

// MARK: - Editor prefill

@Suite("NodeInfoEntity.statusMessagePrefill")
struct StatusMessagePrefillTests {

	@Test func prefersConfiguredWhenDisplayable() {
		#expect(NodeInfoEntity.statusMessagePrefill(configured: "Configured", live: "Live") == "Configured")
	}

	@Test func keepsConfiguredEvenWhenLiveDiffers() {
		#expect(NodeInfoEntity.statusMessagePrefill(configured: "Battery Low", live: nil) == "Battery Low")
	}

	@Test func emptyConfiguredFallsBackToLive() {
		#expect(NodeInfoEntity.statusMessagePrefill(configured: "", live: "Live") == "Live")
	}

	@Test func whitespaceOnlyConfiguredFallsBackToLive() {
		// The case the cards/detail already treat as blank — the editor must agree, not prefill "   ".
		#expect(NodeInfoEntity.statusMessagePrefill(configured: "   \n\t ", live: "Live") == "Live")
	}

	@Test func invisibleOnlyConfiguredFallsBackToLive() {
		#expect(NodeInfoEntity.statusMessagePrefill(configured: "\u{200B}\u{2060}", live: "Live") == "Live")
	}

	@Test func nilConfiguredFallsBackToLive() {
		#expect(NodeInfoEntity.statusMessagePrefill(configured: nil, live: "Live") == "Live")
	}

	@Test func bothBlankReturnsEmpty() {
		// Nothing displayable on either side → normalize to "" rather than surfacing a
		// non-displayable configured/live value.
		#expect(NodeInfoEntity.statusMessagePrefill(configured: "", live: "   ") == "")
	}

	@Test func nonDisplayableConfiguredWithNonDisplayableLiveNormalizesToEmpty() {
		// Whitespace-only configured + invisible-only live → empty, so the editor agrees with the
		// cards/detail (which show nothing) instead of prefilling whitespace that counts bytes.
		#expect(NodeInfoEntity.statusMessagePrefill(configured: "  ", live: "\u{200B}") == "")
	}
}
