//
//  HelpItem.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2025.
//

import SwiftUI

struct HelpItem: View {
	let symbol: AnyView
	let title: String
	let subtitle: String?
	let compact: Bool

	init(symbol: AnyView, title: String, subtitle: String? = nil, compact: Bool = false) {
		self.symbol = symbol
		self.title = title
		self.subtitle = subtitle
		self.compact = compact
	}

	var body: some View {
		HStack(spacing: compact ? 8 : 12) {
			symbol
				.frame(width: compact ? 24 : 40, height: compact ? 24 : 40)
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(compact ? .caption : .subheadline)
					.fontWeight(.medium)
				if let subtitle {
					Text(subtitle)
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
			Spacer()
		}
	}
}
