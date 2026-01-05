import SwiftUI
import UIKit

struct TapbackInputView: View {
	@Binding var text: String
	@Binding var isPresented: Bool
	let onEmojiSelected: (String) -> Void
	
	var body: some View {
		NavigationView {
			VStack(spacing: 0) {
				EmojiOnlyTextField(
					text: $text,
					placeholder: "Tap to enter emoji",
					onBecomeFirstResponder: {
						// Text field will automatically become first responder
					},
					onKeyboardTypeChanged: { shouldDismiss in
						// Dismiss if keyboard switched away from emoji
						if shouldDismiss {
							isPresented = false
						}
					},
					onKeyboardDismissed: {
						// Dismiss sheet when keyboard is dismissed
						isPresented = false
					}
				)
				.frame(height: 50)
				.padding(.horizontal)
				.background(
					RoundedRectangle(cornerRadius: 10)
						.strokeBorder(.tertiary, lineWidth: 1)
						.background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
				)
				.padding(.horizontal)
				.padding(.top, 8)
				.onChange(of: text) { oldValue, newValue in
					// Extract first emoji character and send it
					if !newValue.isEmpty, let firstEmoji = extractFirstEmoji(from: newValue) {
						onEmojiSelected(firstEmoji)
						// Clear the text box after getting the emoji
						text = ""
					}
				}
			}
			.navigationTitle("Tapback")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Cancel") {
						isPresented = false
					}
				}
			}
		}
		.presentationDetents([.height(120)])
	}
	
	private func extractFirstEmoji(from string: String) -> String? {
		// Extract the first emoji character(s) - handle both single and multi-scalar emojis
		guard !string.isEmpty else { return nil }
		
		// Try to get the first character
		let firstChar = string[string.startIndex]
		
		// Check if it's an emoji using the existing extension
		if firstChar.isEmoji {
			// For multi-scalar emojis (like emojis with skin tones), we need to find the full emoji sequence
			var emojiEnd = string.index(after: string.startIndex)
			
			// Check if there are continuation scalars (for emojis with skin tones, variation selectors, etc.)
			while emojiEnd < string.endIndex {
				let nextChar = string[emojiEnd]
				// Check if this is a continuation (variation selector, skin tone modifier, zero-width joiner, etc.)
				if let scalar = nextChar.unicodeScalars.first,
				   (scalar.properties.isVariationSelector ||
					scalar.value == 0xFE0F || // Variation selector
					(scalar.value >= 0x1F3FB && scalar.value <= 0x1F3FF) || // Skin tone modifiers
					scalar.value == 0x200D) { // Zero-width joiner
					emojiEnd = string.index(after: emojiEnd)
				} else if nextChar.isEmoji {
					// If it's another emoji, include it (for compound emojis like flags)
					emojiEnd = string.index(after: emojiEnd)
				} else {
					break
				}
			}
			
			return String(string[string.startIndex..<emojiEnd])
		}
		
		return nil
	}
}

extension UIView {
	var firstResponder: UIView? {
		guard !isFirstResponder else { return self }
		for subview in subviews {
			if let firstResponder = subview.firstResponder {
				return firstResponder
			}
		}
		return nil
	}
}

