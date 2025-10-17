//
//  UnifiedMessageTextView.swift
//  Meshtastic
//
//  A custom text view that renders all messages as a single selectable document
//  This enables text selection across multiple message bubbles
//

import SwiftUI
import UIKit
import MeshtasticProtobufs

/// A UITextView subclass that renders all messages with bubble styling
class MessageTextView: UITextView {
	var messages: [MessageEntity] = []
	var preferredPeripheralNum: Int = 0
	var onMessageTap: ((MessageEntity) -> Void)?
	var onReply: ((MessageEntity) -> Void)?
	
	override init(frame: CGRect, textContainer: NSTextContainer?) {
		super.init(frame: frame, textContainer: textContainer)
		setupTextView()
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupTextView()
	}
	
	private func setupTextView() {
		isEditable = false
		isSelectable = true
		isScrollEnabled = true
		backgroundColor = .clear
		textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
		textContainer.lineFragmentPadding = 0
		dataDetectorTypes = .link
		isUserInteractionEnabled = true
		adjustsFontForContentSizeCategory = true
	}
	
	func renderMessages() {
		let attributedString = NSMutableAttributedString()
		
		for (index, message) in messages.enumerated() {
			let isCurrentUser = Int64(preferredPeripheralNum) == message.fromUser?.num
			let previousMessage = index > 0 ? messages[index - 1] : nil
			
			// Add timestamp if needed
			if message.displayTimestamp(aboveMessage: previousMessage) {
				let timestampText = message.timestamp.formatted(date: .abbreviated, time: .shortened)
				let timestampAttrs = createTimestampAttributes()
				attributedString.append(NSAttributedString(string: "\n\(timestampText)\n\n", attributes: timestampAttrs))
			}
			
			// Add sender name for non-current user messages
			if !isCurrentUser && message.fromUser != nil {
				let senderText = "\(message.fromUser?.longName ?? "Unknown") (\(message.fromUser?.userId ?? "?"))"
				let senderAttrs = createSenderAttributes()
				attributedString.append(NSAttributedString(string: "\(senderText)\n", attributes: senderAttrs))
			}
			
			// Add message content with bubble styling
			let messageContent = createMessageAttributedString(message: message, isCurrentUser: isCurrentUser)
			attributedString.append(messageContent)
			
			// Add spacing after message
			attributedString.append(NSAttributedString(string: "\n\n"))
		}
		
		attributedText = attributedString
	}
	
	private func createTimestampAttributes() -> [NSAttributedString.Key: Any] {
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.alignment = .center
		paragraphStyle.paragraphSpacing = 5
		
		return [
			.font: UIFont.preferredFont(forTextStyle: .caption1),
			.foregroundColor: UIColor.systemGray,
			.paragraphStyle: paragraphStyle
		]
	}
	
	private func createSenderAttributes() -> [NSAttributedString.Key: Any] {
		return [
			.font: UIFont.preferredFont(forTextStyle: .caption1),
			.foregroundColor: UIColor.systemGray
		]
	}
	
	private func createMessageAttributedString(message: MessageEntity, isCurrentUser: Bool) -> NSAttributedString {
		let messageText = message.messagePayload ?? "EMPTY MESSAGE"
		let backgroundColor = isCurrentUser ? UIColor.systemBlue : UIColor.systemGray
		
		// Create paragraph style for bubble effect
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.paragraphSpacing = 8
		paragraphStyle.headIndent = 12
		paragraphStyle.tailIndent = isCurrentUser ? -12 : 0
		paragraphStyle.firstLineHeadIndent = 12
		
		let baseAttributes: [NSAttributedString.Key: Any] = [
			.font: UIFont.preferredFont(forTextStyle: .body),
			.foregroundColor: UIColor.white,
			.backgroundColor: backgroundColor,
			.paragraphStyle: paragraphStyle
		]
		
		// Parse markdown if available
		if let markdown = message.messagePayloadMarkdown,
		   let parsedText = try? AttributedString(
			markdown: markdown,
			options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
		   ) {
			let mutableAttrString = NSMutableAttributedString(parsedText)
			// Add base attributes
			mutableAttrString.addAttributes(baseAttributes, range: NSRange(location: 0, length: mutableAttrString.length))
			return mutableAttrString
		} else {
			return NSAttributedString(string: messageText, attributes: baseAttributes)
		}
	}
}

/// SwiftUI wrapper for the unified message text view
struct UnifiedMessageTextView: UIViewRepresentable {
	let messages: [MessageEntity]
	let preferredPeripheralNum: Int
	@Binding var scrollToBottom: Bool
	
	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}
	
	func makeUIView(context: Context) -> MessageTextView {
		let textView = MessageTextView()
		textView.delegate = context.coordinator
		return textView
	}
	
	func updateUIView(_ uiView: MessageTextView, context: Context) {
		uiView.messages = messages
		uiView.preferredPeripheralNum = preferredPeripheralNum
		uiView.renderMessages()
		
		if scrollToBottom {
			DispatchQueue.main.async {
				scrollToBottom = false
				let bottom = NSRange(location: uiView.text.count - 1, length: 1)
				uiView.scrollRangeToVisible(bottom)
			}
		}
	}
	
	class Coordinator: NSObject, UITextViewDelegate {
		var parent: UnifiedMessageTextView
		
		init(_ parent: UnifiedMessageTextView) {
			self.parent = parent
		}
		
		func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
			// Handle URL taps
			handleURL(URL)
			return false
		}
		
		private func handleURL(_ url: URL) {
			if url.absoluteString.lowercased().contains("meshtastic.org/v/#") {
				ContactURLHandler.handleContactUrl(url: url, accessoryManager: AccessoryManager.shared)
			} else if url.absoluteString.lowercased().contains("meshtastic.org/e/") {
				// Handle channel URL - would need to pass this up to the parent view
				UIApplication.shared.open(url)
			} else {
				UIApplication.shared.open(url)
			}
		}
	}
}
