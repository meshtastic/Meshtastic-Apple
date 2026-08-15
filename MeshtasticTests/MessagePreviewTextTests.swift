import Foundation
import Testing

@testable import Meshtastic

@Suite("Message preview text")
struct MessagePreviewTextTests {

	@Test("Bare URLs are not interactive in conversation previews")
	func bareURLIsNotInteractive() {
		let source = "See https://meshtastic.org/docs for details"
		let preview = MessagePreviewText.attributedString(for: source)

		#expect(String(preview.characters) == source)
		#expect(preview.runs.allSatisfy { $0.link == nil })
	}

	@Test("Markdown links keep their label without remaining interactive")
	func markdownLinkIsNotInteractive() {
		let preview = MessagePreviewText.attributedString(
			for: "Read the [Meshtastic docs](https://meshtastic.org/docs)"
		)

		#expect(String(preview.characters) == "Read the Meshtastic docs")
		#expect(preview.runs.allSatisfy { $0.link == nil })
	}
}
