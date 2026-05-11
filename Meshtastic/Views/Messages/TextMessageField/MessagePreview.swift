// MARK: MessagePreview

import SwiftUI

struct MessagePreview: View {
	let text: String

	var body: some View {
		if containsMarkdownSyntax(text) {
			HStack {
				Spacer()
				Text(LocalizedStringKey(text))
					.tint(.white)
					.padding(.vertical, 10)
					.padding(.horizontal, 8)
					.foregroundColor(.white)
					.background(Color.accentColor)
					.cornerRadius(15)
			}
			.padding(.horizontal, 15)
			.padding(.bottom, 4)
			.allowsHitTesting(false)
		}
	}
}
