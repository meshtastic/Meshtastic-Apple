//
//  SecureInput.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/12/24.
//

import SwiftUI

struct SecureInput: View {

	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	private var textStyle: Font.TextStyle { idiom == .phone ? .caption : .callout }
	@Binding private var text: String
	@Binding private var isValid: Bool
	private var title: String

	// Local state to store the value of iSSecure, or optionally a binding
	private var isSecureBinding: Binding<Bool>?
	@State private var isSecureLocal: Bool = true

	private var isSecure: Binding<Bool> {
		// Use the binding if we have one, otherwise fallback to the local state variable
		isSecureBinding ?? $isSecureLocal
	}

	init(_ title: String, text: Binding<String>, isValid: Binding<Bool>, isSecure: Binding<Bool>? = nil) {
		self.title = title
		self._text = text
		self._isValid = isValid
		self.isSecureBinding = isSecure
	}

	var body: some View {
		ZStack(alignment: .trailing) {
			Group {
				if isSecure.wrappedValue {
					SecureField(title, text: $text)
						.font(.system(textStyle, design: .monospaced))
						.allowsTightening(true)
						.keyboardType(.alphabet)
						.foregroundStyle(.tertiary)
						.disableAutocorrection(true)
				} else {
					TextField(title, text: $text, axis: .vertical)
						.font(.system(textStyle, design: .monospaced))
						.allowsTightening(true)
						.keyboardType(.alphabet)
						.foregroundStyle(.tertiary)
						.disableAutocorrection(true)
						.textSelection(.enabled)
						.backport.apply { field in
							if #available(iOS 16.0, *) {
								field.lineLimit(...3)
							} else {
								field.lineLimit(3)
							}
						}
						.background(
							RoundedRectangle(cornerRadius: 10.0)
								.stroke(isValid ? Color.clear : Color.red, lineWidth: 2.0)
						)
				}
			}.padding(.trailing, 36)

			if !text.isEmpty {
				Button(action: {
					isSecure.wrappedValue.toggle()
				}) {
					Image(systemName: self.isSecure.wrappedValue ? "eye.slash" : "eye")
						.accentColor(.secondary)
				}.buttonStyle(BorderlessButtonStyle())
			}
		}
	}
}
