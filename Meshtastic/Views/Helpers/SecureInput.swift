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
	@State private var isSecure: Bool = true
	private var title: String

	init(_ title: String, text: Binding<String>) {
		self.title = title
		self._text = text
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
						.textSelection(.enabled)
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
