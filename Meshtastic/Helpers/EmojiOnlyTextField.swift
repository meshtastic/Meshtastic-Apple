//
//  EmojiKeyboard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 1/10/23.
//
import SwiftUI

class SwiftUIEmojiTextField: UITextField {

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
}

struct EmojiOnlyTextField: UIViewRepresentable {
	@Binding var text: String
	var placeholder: String = ""

	func makeUIView(context: Context) -> SwiftUIEmojiTextField {
		let emojiTextField = SwiftUIEmojiTextField()
		emojiTextField.placeholder = placeholder
		emojiTextField.text = text
		emojiTextField.delegate = context.coordinator
		return emojiTextField
	}

	func updateUIView(_ uiView: SwiftUIEmojiTextField, context: Context) {
		uiView.text = text
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	class Coordinator: NSObject, UITextFieldDelegate {
		var parent: EmojiOnlyTextField
		init(parent: EmojiOnlyTextField) {
			self.parent = parent
		}
		func textFieldDidChangeSelection(_ textField: UITextField) {
			DispatchQueue.main.async { [weak self] in
				self?.parent.text = textField.text ?? ""
			}
		}
	}
}
