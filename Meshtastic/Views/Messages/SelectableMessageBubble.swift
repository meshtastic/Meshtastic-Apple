//
//  SelectableMessageBubble.swift
//  Meshtastic
//
//  A message bubble with selectable text that integrates properly with SwiftUI layout
//

import SwiftUI
import UIKit

struct SelectableMessageBubble: UIViewRepresentable {
	let text: String
	let markdown: String?
	let isCurrentUser: Bool
	let onURLTap: (URL) -> Void
	
	func makeCoordinator() -> Coordinator {
		Coordinator(onURLTap: onURLTap)
	}
	
	func makeUIView(context: Context) -> BubbleTextView {
		let textView = BubbleTextView()
		textView.delegate = context.coordinator
		
		// Set maximum width to about 70% of screen width
		// This matches typical messaging app bubble widths
		let maxWidth: CGFloat = 400 // Reasonable max for bubbles
		textView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth).isActive = true
		
		return textView
	}
	
	func updateUIView(_ uiView: BubbleTextView, context: Context) {
		uiView.configure(
			text: text,
			markdown: markdown,
			backgroundColor: isCurrentUser ? UIColor.systemBlue : UIColor.systemGray
		)
	}
	
	class Coordinator: NSObject, UITextViewDelegate {
		let onURLTap: (URL) -> Void
		
		init(onURLTap: @escaping (URL) -> Void) {
			self.onURLTap = onURLTap
		}
		
		func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
			onURLTap(URL)
			return false
		}
	}
}

class BubbleTextView: UITextView {
	
	override init(frame: CGRect, textContainer: NSTextContainer?) {
		super.init(frame: frame, textContainer: textContainer)
		setupView()
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupView()
	}
	
	private func setupView() {
		isEditable = false
		isSelectable = true
		isScrollEnabled = false
		textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
		textContainer.lineFragmentPadding = 0
		textContainer.lineBreakMode = .byWordWrapping
		dataDetectorTypes = .link
		isUserInteractionEnabled = true
		adjustsFontForContentSizeCategory = true
		layer.cornerRadius = 15
		clipsToBounds = true
		linkTextAttributes = [
			.foregroundColor: UIColor(red: 0.4627, green: 0.8392, blue: 1, alpha: 1),
			.underlineStyle: NSUnderlineStyle.single.rawValue
		]
		
		// Set a maximum width constraint
		translatesAutoresizingMaskIntoConstraints = false
	}
	
	func configure(text: String, markdown: String?, backgroundColor: UIColor) {
		self.backgroundColor = backgroundColor
		
		let bodyFont = UIFont.preferredFont(forTextStyle: .body)
		
		// Try to parse markdown first
		if let markdown = markdown,
		   let attributedText = parseMarkdown(markdown, font: bodyFont) {
			self.attributedText = attributedText
		} else {
			// Fallback to plain text
			self.text = text
			self.textColor = .white
			self.font = bodyFont
		}
		
		// Force the text container to use the view's width for wrapping
		textContainer.size = CGSize(width: bounds.width > 0 ? bounds.width - (textContainerInset.left + textContainerInset.right) : 400, height: .greatestFiniteMagnitude)
		
		invalidateIntrinsicContentSize()
		layoutManager.ensureLayout(for: textContainer)
	}
	
	private func parseMarkdown(_ text: String, font: UIFont) -> NSAttributedString? {
		do {
			// Use options that preserve whitespace and interpret newlines as line breaks
			var attributedString = try AttributedString(
				markdown: text,
				options: AttributedString.MarkdownParsingOptions(
					interpretedSyntax: .inlineOnlyPreservingWhitespace
				)
			)
			
			attributedString.foregroundColor = .white
			attributedString.font = Font(font as CTFont)
			
			let nsAttributedString = NSMutableAttributedString(attributedString)
			
			// Add paragraph style to preserve line breaks
			let paragraphStyle = NSMutableParagraphStyle()
			paragraphStyle.lineBreakMode = .byWordWrapping
			
			nsAttributedString.addAttributes([
				.font: font,
				.foregroundColor: UIColor.white,
				.paragraphStyle: paragraphStyle
			], range: NSRange(location: 0, length: nsAttributedString.length))
			
			return nsAttributedString
		} catch {
			return nil
		}
	}
	
	override var intrinsicContentSize: CGSize {
		// Calculate size based on content
		let size = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
		return CGSize(width: size.width, height: size.height)
	}
}
