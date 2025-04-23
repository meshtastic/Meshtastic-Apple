//
//  ScrollToBottomButtonView.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 4/2/25.
//

import SwiftUI

struct ScrollToBottomButtonView: View {
    var body: some View {
		HStack(spacing: 4) {
			Text("Jump to present")
				.font(.caption)
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
				.cornerRadius(12)
			Image(systemName: "arrow.down")
				.font(.title2)
				.symbolRenderingMode(.hierarchical)

		}
		.foregroundColor(.accentColor)
		.shadow(radius: 2)
    }
}

#Preview {
    ScrollToBottomButtonView()
}
