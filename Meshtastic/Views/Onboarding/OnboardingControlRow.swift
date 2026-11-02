//
//  OnboardingControlRow.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//
//  A setup row with a control at its trailing edge: the same symbol, title and text as
//  `OnboardingFeatureRow`, with a picker or value where that row puts a switch.
//

import SwiftUI

struct OnboardingControlRow<Control: View>: View {
	let symbol: String
	let color: Color
	let title: String
	let text: String?
	let control: () -> Control

	@Environment(\.dynamicTypeSize) private var dynamicTypeSize
	@ScaledMetric(relativeTo: .title) private var symbolSize: CGFloat = 34
	@ScaledMetric(relativeTo: .title) private var symbolColumn: CGFloat = 56

	init(
		symbol: String,
		color: Color = .accentColor,
		title: String,
		text: String? = nil,
		@ViewBuilder control: @escaping () -> Control
	) {
		self.symbol = symbol
		self.color = color
		self.title = title
		self.text = text
		self.control = control
	}

	var body: some View {
		// At accessibility sizes everything stacks, so nothing is squeezed beside the text.
		if dynamicTypeSize.isAccessibilitySize {
			VStack(alignment: .leading, spacing: 8) {
				icon
				titleAndText
				control()
					.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		} else {
			HStack(alignment: .center, spacing: 12) {
				icon
				titleAndText
				// The row's control is the tap target, so it gets the minimum height.
				control()
					.frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	private var icon: some View {
		Image(systemName: symbol)
			.font(.system(size: symbolSize))
			.foregroundStyle(color)
			.frame(width: symbolColumn)
			// Decorative: the title says what the row is.
			.accessibilityHidden(true)
	}

	private var titleAndText: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(title)
				.font(.headline)
			if let text {
				Text(text)
					.font(.body)
			}
		}
		.foregroundStyle(.primary)
		.multilineTextAlignment(.leading)
		.fixedSize(horizontal: false, vertical: true)
	}
}

#Preview("Control rows") {
	@Previewable @State var region = 1
	VStack(alignment: .leading, spacing: 24) {
		OnboardingControlRow(symbol: "globe.americas.fill", color: .red, title: "Region") {
			Picker("Region", selection: $region) {
				Text("United States").tag(1)
				Text("European Union 868").tag(3)
			}
			.labelsHidden()
		}
		OnboardingControlRow(symbol: "dot.radiowaves.left.and.right", title: "Preset", text: "Recommended for United States: Long Range - Turbo") {
			Picker("Preset", selection: $region) {
				Text("Long Range - Turbo").tag(1)
				Text("Long Range - Fast").tag(3)
			}
			.labelsHidden()
		}
	}
	.padding(24)
}
