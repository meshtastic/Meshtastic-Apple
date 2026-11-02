//
//  OnboardingFeatureRow.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
//  One feature row of a setup page: a colored symbol, a short title, body text and an
//  optional switch. Takes plain values and bindings only, so any setup flow can use it.
//

import SwiftUI

struct OnboardingFeatureRow: View {
	/// An SF Symbol name, or "custom.<name>" for a symbol set in the asset catalog.
	let symbol: String
	let color: Color
	let title: String?
	let text: String
	let isOn: Binding<Bool>?

	@Environment(\.dynamicTypeSize) private var dynamicTypeSize
	@ScaledMetric(relativeTo: .title) private var symbolSize: CGFloat = 34
	@ScaledMetric(relativeTo: .title) private var symbolColumn: CGFloat = 56

	init(
		symbol: String,
		color: Color = .accentColor,
		title: String? = nil,
		text: String,
		isOn: Binding<Bool>? = nil
	) {
		self.symbol = symbol
		self.color = color
		self.title = title
		self.text = text
		self.isOn = isOn
	}

	var body: some View {
		// At accessibility sizes the symbol column would leave too little width for the
		// text, so the row stacks instead.
		let layout = dynamicTypeSize.isAccessibilitySize
			? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
			: AnyLayout(HStackLayout(alignment: .center, spacing: 12))
		layout {
			icon
			VStack(alignment: .leading, spacing: 2) {
				if let title {
					Text(title)
						.font(.headline)
				}
				Text(text)
					.font(.body)
			}
			.foregroundStyle(.primary)
			.multilineTextAlignment(.leading)
			.fixedSize(horizontal: false, vertical: true)
			if let isOn {
				Spacer(minLength: 0)
				Toggle("", isOn: isOn)
					.labelsHidden()
					.fixedSize()
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.accessibilityElement(children: .combine)
	}

	@ViewBuilder
	private var icon: some View {
		Group {
			if symbol.hasPrefix("custom.") {
				Image(symbol)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: symbolSize, height: symbolSize)
			} else {
				Image(systemName: symbol)
					.font(.system(size: symbolSize))
			}
		}
		.foregroundStyle(color)
		.frame(width: symbolColumn)
		// Decorative: the title and text say what the row is.
		.accessibilityHidden(true)
	}
}

#Preview("Rows") {
	@Previewable @State var isOn = true
	VStack(alignment: .leading, spacing: 24) {
		OnboardingFeatureRow(
			symbol: "antenna.radiowaves.left.and.right",
			color: .green,
			title: "Off-Grid Messaging",
			text: "Send text, positions and more over LoRa radios. No cell service or internet needed."
		)
		OnboardingFeatureRow(
			symbol: "custom.bluetooth",
			color: .teal,
			title: "Bluetooth Connected Nodes",
			text: "The most reliable messaging experience is with Bluetooth Low Energy connected nodes."
		)
		OnboardingFeatureRow(
			symbol: "message",
			title: "Incoming Messages",
			text: "Notifications for channel and direct messages.",
			isOn: $isOn
		)
		OnboardingFeatureRow(
			symbol: "exclamationmark.triangle.fill",
			color: .red,
			text: "Select packets sent as critical will ignore the mute switch and Do Not Disturb settings."
		)
	}
	.padding(24)
}
