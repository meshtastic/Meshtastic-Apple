//
//  OnboardingControlRow.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//
//  A setup row with a control at its trailing edge: the same symbol, title and text as
//  `OnboardingFeatureRow`, with a picker, text field or value where that row puts a switch.
//

import SwiftUI

struct OnboardingControlRow<Control: View>: View {
	/// Where the control sits at regular text sizes. A picker or value fits beside the
	/// title; a text field needs the row's width, so it goes under the title.
	enum Placement {
		case trailing, below
	}

	let symbol: String
	let color: Color
	let title: String
	let text: String?
	let placement: Placement
	let control: () -> Control

	@Environment(\.dynamicTypeSize) private var dynamicTypeSize
	@ScaledMetric(relativeTo: .title) private var symbolSize: CGFloat = 34
	@ScaledMetric(relativeTo: .title) private var symbolColumn: CGFloat = 56

	init(
		symbol: String,
		color: Color = .accentColor,
		title: String,
		text: String? = nil,
		placement: Placement = .trailing,
		@ViewBuilder control: @escaping () -> Control
	) {
		self.symbol = symbol
		self.color = color
		self.title = title
		self.text = text
		self.placement = placement
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
		} else if placement == .below {
			HStack(alignment: .center, spacing: 12) {
				icon
				VStack(alignment: .leading, spacing: 8) {
					titleAndText
					control()
						.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
				}
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
	@Previewable @State var name = "Meshtastic 1234"
	VStack(alignment: .leading, spacing: 24) {
		OnboardingControlRow(symbol: "globe.americas.fill", color: .red, title: "Region") {
			Picker("Region", selection: $region) {
				Text("United States").tag(1)
				Text("European Union 868").tag(3)
			}
			.labelsHidden()
		}
		OnboardingControlRow(symbol: "person.crop.rectangle.fill", color: .indigo, title: "Long Name", text: "Up to 24 bytes.", placement: .below) {
			TextField("Long Name", text: $name)
				.textFieldStyle(.roundedBorder)
		}
	}
	.padding(24)
}
