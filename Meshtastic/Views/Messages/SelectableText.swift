//
//  SelectableText.swift
//  Meshtastic
//
//  Created for text selection support in message bubbles
//

import SwiftUI
import UIKit

/// A wrapper view that provides proper sizing for SelectableTextView
struct SelectableText: View {
	let text: String
	let markdown: Bool
	let textColor: UIColor
	let linkColor: UIColor
	let onLinkTap: ((URL) -> Bool)?
	
	init(text: String, markdown: Bool = true, textColor: UIColor = .white, linkColor: UIColor = UIColor(red: 0.4627, green: 0.8392, blue: 1, alpha: 1), onLinkTap: ((URL) -> Bool)? = nil) {
		self.text = text
		self.markdown = markdown
		self.textColor = textColor
		self.linkColor = linkColor
		self.onLinkTap = onLinkTap
	}
	
	var body: some View {
		GeometryReader { geometry in
			SelectableTextView(
				text: text,
				markdown: markdown,
				textColor: textColor,
				linkColor: linkColor,
				maxWidth: geometry.size.width,
				onLinkTap: onLinkTap
			)
		}
	}
}

/// Internal UIViewRepresentable that does the actual text rendering
struct SelectableTextView: UIViewRepresentable {
	let text: String
	let markdown: Bool
	let textColor: UIColor
	let linkColor: UIColor
	let maxWidth: CGFloat
	let onLinkTap: ((URL) -> Bool)?
	
	func makeCoordinator() -> Coordinator {
		Coordinator(onLinkTap: onLinkTap)
	}
	
	class Coordinator: NSObject, UITextViewDelegate {
		let onLinkTap: ((URL) -> Bool)?
		
		init(onLinkTap: ((URL) -> Bool)?) {
			self.onLinkTap = onLinkTap
		}
		
		func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
			if let handler = onLinkTap {
				return handler(URL)
			}
			return true
		}
	}
	
	func makeUIView(context: Context) -> UITextView {
		let textView = UITextView()
		textView.delegate = context.coordinator
		textView.isEditable = false
		textView.isSelectable = true
		textView.isScrollEnabled = false
		textView.backgroundColor = .clear
		textView.textContainerInset = .zero
		textView.textContainer.lineFragmentPadding = 0
		textView.dataDetectorTypes = .link
		textView.linkTextAttributes = [
			.foregroundColor: linkColor,
			.underlineStyle: NSUnderlineStyle.single.rawValue
		]
		
		// Enable text wrapping - this is crucial
		textView.textContainer.lineBreakMode = .byWordWrapping
		textView.textContainer.maximumNumberOfLines = 0 // Allow unlimited lines
		
		// Allow text selection to work properly
		textView.isUserInteractionEnabled = true
		
		// Make the textView respect dynamic type
		textView.adjustsFontForContentSizeCategory = true
		
		return textView
	}
	
	func updateUIView(_ uiView: UITextView, context: Context) {
		// Use the system preferred font for body text to match SwiftUI Text default
		// This automatically adapts to user's preferred text size and platform
		let bodyFont = UIFont.preferredFont(forTextStyle: .body)
		
		// Set the text container width to match the available width
		uiView.textContainer.size = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
		
		if markdown {
			// Parse markdown and create attributed string
			if let attributedString = parseMarkdown(text, font: bodyFont) {
				uiView.attributedText = attributedString
			} else {
				// Fallback to plain text
				uiView.text = text
				uiView.textColor = textColor
				uiView.font = bodyFont
			}
		} else {
			uiView.text = text
			uiView.textColor = textColor
			uiView.font = bodyFont
		}
		
		// Force layout update
		uiView.invalidateIntrinsicContentSize()
		uiView.layoutManager.ensureLayout(for: uiView.textContainer)
	}
	
	private func parseMarkdown(_ text: String, font: UIFont) -> NSAttributedString? {
		// Use AttributedString to parse markdown, then convert to NSAttributedString
		do {
			var attributedString = try AttributedString(markdown: text)
			
			// Apply base styling - use the system font size
			attributedString.foregroundColor = Color(textColor)
			attributedString.font = Font(font as CTFont)
			
			// Convert to NSAttributedString
			let nsAttributedString = NSMutableAttributedString(attributedString)
			
			// Ensure all text has the proper font and color
			nsAttributedString.addAttributes([
				.font: font,
				.foregroundColor: textColor
			], range: NSRange(location: 0, length: nsAttributedString.length))
			
			return nsAttributedString
		} catch {
			return nil
		}
	}
}
