import SwiftUI

struct MessagePreviewText: View {

	private let text: AttributedString

	init(_ source: String) {
		text = Self.attributedString(for: source)
	}

	var body: some View {
		Text(text)
	}

	static func attributedString(for source: String) -> AttributedString {
		guard var result = try? AttributedString(
			markdown: source,
			options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
		) else {
			return AttributedString(source)
		}

		let linkRanges = result.runs.compactMap { run in
			run.link == nil ? nil : run.range
		}
		for range in linkRanges {
			result[range].link = nil
		}
		return result
	}
}
