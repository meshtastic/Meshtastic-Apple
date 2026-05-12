// MARK: FormattingToolbarButtons

import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
struct FormattingToolbarButtons: View {
	@Binding var typingMessage: String
	@Binding var textSelection: TextSelection?
	@Binding var showLinkAlert: Bool

	@State private var linkURL: String = ""
	@State private var pendingLinkRange: Range<String.Index>?

	var body: some View {
		Group {
			ForEach(MarkdownStyle.allCases, id: \.self) { style in
				Button {
					applyFormatting(style: style)
				} label: {
					Image(systemName: style.sfSymbol)
						.frame(minWidth: 44, minHeight: 36)
						.foregroundColor(.primary)
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel(accessibilityLabel(for: style))
				.disabled(textSelection == nil)
			}
		}
		.alert("Insert Link", isPresented: $showLinkAlert) {
			TextField("https://", text: $linkURL)
				.textInputAutocapitalization(.never)
				.keyboardType(.URL)
			Button("Cancel", role: .cancel) {
				linkURL = ""
				pendingLinkRange = nil
			}
			Button("Insert") {
				if let range = pendingLinkRange {
					let result = wrapSelectionWithLink(in: typingMessage, range: range, url: linkURL)
					typingMessage = result.text
					textSelection = TextSelection(range: result.selectedRange)
				}
				linkURL = ""
				pendingLinkRange = nil
			}
			.disabled(linkURL.isEmpty)
		} message: {
			Text("Enter the URL for the selected text")
		}
	}

	// MARK: - Formatting Logic

	private func applyFormatting(style: MarkdownStyle) {
		guard let textSelection else { return }

		switch textSelection.indices {
		case .selection(let range):
			if style == .link {
				let lower = stringIndex(from: range.lowerBound)
				let upper = stringIndex(from: range.upperBound)
				let selectedText = String(typingMessage[lower..<upper])
				if isMarkdownLink(selectedText) {
					// Toggle off — unwrap link
					if let result = unwrapLink(in: typingMessage, range: lower..<upper) {
						typingMessage = result.text
						self.textSelection = TextSelection(range: result.selectedRange)
					}
				} else {
					// Show URL entry dialog
					pendingLinkRange = lower..<upper
					showLinkAlert = true
				}
				return
			}

			if range.lowerBound == range.upperBound {
				// Collapsed cursor — insert delimiters
				let stringIndex = stringIndex(from: range.lowerBound)
				let result = insertDelimiters(in: typingMessage, at: stringIndex, style: style)
				typingMessage = result.text
				self.textSelection = TextSelection(range: result.selectedRange)
			} else {
				// Non-empty selection — wrap/unwrap
				let lower = stringIndex(from: range.lowerBound)
				let upper = stringIndex(from: range.upperBound)
				let result = wrapSelection(in: typingMessage, range: lower..<upper, style: style)
				typingMessage = result.text
				self.textSelection = TextSelection(range: result.selectedRange)
			}
		default:
			break
		}
	}

	private func stringIndex(from index: String.Index) -> String.Index {
		guard !typingMessage.isEmpty else { return typingMessage.startIndex }
		if index <= typingMessage.startIndex { return typingMessage.startIndex }
		if index >= typingMessage.endIndex { return typingMessage.endIndex }
		if let match = typingMessage.indices.first(where: { $0 >= index }) {
			return match
		}
		return typingMessage.endIndex
	}

	private func accessibilityLabel(for style: MarkdownStyle) -> String {
		switch style {
		case .bold: return "Bold"
		case .italic: return "Italic"
		case .strikethrough: return "Strikethrough"
		case .code: return "Code"
		case .link: return "Link"
		}
	}
}
