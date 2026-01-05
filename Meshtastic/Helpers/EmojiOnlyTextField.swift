//
//  EmojiKeyboard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 1/10/23.
//
import SwiftUI

class SwiftUIEmojiTextField: UITextField {
	var shouldBecomeFirstResponderOnAppear = false

	func setEmoji() {
		_ = self.textInputMode
	}

	override var textInputContextIdentifier: String? {
		return ""
	}

	override var textInputMode: UITextInputMode? {
		for mode in UITextInputMode.activeInputModes where mode.primaryLanguage == "emoji" {
			self.keyboardType = .default // do not remove this
			return mode
		}
		return nil
	}
	
	override func didMoveToWindow() {
		super.didMoveToWindow()
		if shouldBecomeFirstResponderOnAppear && window != nil {
			DispatchQueue.main.async { [weak self] in
				self?.becomeFirstResponder()
			}
		}
	}
}

struct EmojiOnlyTextField: UIViewRepresentable {
	@Binding var text: String
	var placeholder: String = ""
	var onBecomeFirstResponder: (() -> Void)?
	var onKeyboardTypeChanged: ((Bool) -> Void)? // true if emoji, false otherwise
	var onKeyboardDismissed: (() -> Void)? // Called when keyboard is dismissed

	func makeUIView(context: Context) -> SwiftUIEmojiTextField {
		let emojiTextField = SwiftUIEmojiTextField()
		emojiTextField.placeholder = placeholder
		emojiTextField.text = text
		emojiTextField.delegate = context.coordinator
		emojiTextField.shouldBecomeFirstResponderOnAppear = true
		context.coordinator.textField = emojiTextField
		return emojiTextField
	}

	func updateUIView(_ uiView: SwiftUIEmojiTextField, context: Context) {
		uiView.text = text
		context.coordinator.onBecomeFirstResponder = onBecomeFirstResponder
		context.coordinator.onKeyboardTypeChanged = onKeyboardTypeChanged
		context.coordinator.onKeyboardDismissed = onKeyboardDismissed
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	class Coordinator: NSObject, UITextFieldDelegate {
		var parent: EmojiOnlyTextField
		var textField: SwiftUIEmojiTextField?
		var onBecomeFirstResponder: (() -> Void)?
		var onKeyboardTypeChanged: ((Bool) -> Void)?
		var onKeyboardDismissed: (() -> Void)?
		var previousInputMode: String?
		
		init(parent: EmojiOnlyTextField) {
			self.parent = parent
		}
		
		func textFieldDidBeginEditing(_ textField: UITextField) {
			onBecomeFirstResponder?()
			checkInputMode(textField)
		}
		
		func textFieldDidEndEditing(_ textField: UITextField) {
			// Keyboard was dismissed
			onKeyboardDismissed?()
		}
		
		func textFieldDidChangeSelection(_ textField: UITextField) {
			DispatchQueue.main.async { [weak self] in
				self?.parent.text = textField.text ?? ""
			}
			checkInputMode(textField)
		}
		
		private func checkInputMode(_ textField: UITextField) {
			if let inputMode = textField.textInputMode {
				let isEmoji = inputMode.primaryLanguage == "emoji"
				if previousInputMode != inputMode.primaryLanguage {
					previousInputMode = inputMode.primaryLanguage
					onKeyboardTypeChanged?(!isEmoji) // true if NOT emoji (should dismiss)
				}
			}
		}
	}
}
