//
//  Untitled.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 6/19/25.
//
import TipKit

struct PersistentTip: TipViewStyle {
	func makeBody(configuration: Configuration) -> some View {
		VStack {
			HStack(alignment: .top) {
				if let image = configuration.image {
					image
						.font(.system(size: 42))
						.foregroundColor(.accentColor)
						.padding(.trailing, 5)
				}
				VStack(alignment: .leading) {
					if let title = configuration.title {
						title
							.bold()
							.font(.headline)
					}
					if let message = configuration.message {
						message
							.foregroundStyle(.secondary)
							.font(.callout)
					}
				}
			}
		}
		.frame(maxWidth: .infinity)
		.backgroundStyle(.thinMaterial)
		.padding()
	}
}
