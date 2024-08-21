//
//  SecureInput.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/12/24.
//

import SwiftUI

struct SecureInput: View {

	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Binding private var text: String
	@Binding private var isValid: Bool
	@State private var isSecure: Bool = true
	private var title: String

	init(_ title: String, text: Binding<String>, isValid: Binding<Bool>) {
		self.title = title
		self._text = text
		self._isValid = isValid
	}

	var body: some View {
		ZStack(alignment: .trailing) {
			Group {
				if isSecure {
					SecureField(title, text: $text)
						.font(idiom == .phone ? .caption : .callout)
						.allowsTightening(true)
						.monospaced()
						.keyboardType(.alphabet)
						.foregroundStyle(.tertiary)
						.disableAutocorrection(true)
				} else {
					TextField(title, text: $text, axis: .vertical)
						.font(idiom == .phone ? .caption : .callout)
						.allowsTightening(true)
						.monospaced()
						.keyboardType(.alphabet)
						.foregroundStyle(.tertiary)
						.disableAutocorrection(true)
						.textSelection(.enabled)
						.lineLimit(...3)
						.background(
							RoundedRectangle(cornerRadius: 10.0)
								.stroke(isValid ? Color.clear : Color.red, lineWidth: 2.0)
						)
				}
			}.padding(.trailing, 36)

			if !text.isEmpty {
				Button(action: {
					isSecure.toggle()
				}) {
					Image(systemName: self.isSecure ? "eye.slash" : "eye")
						.accentColor(.secondary)
				}
			}
		}
	}
}
