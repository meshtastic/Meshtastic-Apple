//
//  ReadingCompactWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//

import SwiftUI

/// A compact tile for a reading with no tile of its own, such as dew point,
/// gas resistance, IAQ or light, laid out like the weight and radiation tiles.
struct ReadingCompactWidget: View {
	let systemImage: String
	/// Already localized.
	let title: String
	let value: String
	var unit: String?
	/// A line under the value: the IAQ band.
	var detail: String?
	var valueColor: Color?

	private var fillsTile: Bool { unit == nil && value.count < 4 }

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Image(systemName: systemImage)
					.imageScale(.small)
					.foregroundColor(.accentColor)
				// Long names such as gas resistance wrap rather than shrink.
				Text(verbatim: title)
					.textCase(.uppercase)
					.font(.callout)
					.lineLimit(2)
					.minimumScaleFactor(0.5)
			}
			HStack {
				Group {
					if fillsTile {
						// A short reading with no unit beside it, such as IAQ, grows to fill the
						// space between the title and its band.
						Text(value)
							.font(.system(size: 200))
							.minimumScaleFactor(0.1)
							.frame(maxHeight: .infinity, alignment: .leading)
					} else {
						Text(value)
							.font(value.count < 4 ? .system(size: 50) : .system(size: 40))
					}
				}
				.foregroundStyle(valueColor ?? Color(uiColor: .label))
				if let unit {
					Text(unit)
						.font(.system(size: 14))
				}
			}
			if let detail {
				// A band, such as IAQ's, gets a dot in its color, as the CO2 tile does.
				HStack(spacing: 4) {
					if let valueColor {
						Circle()
							.fill(valueColor)
							.frame(width: 8, height: 8)
							.accessibilityHidden(true)
					}
					Text(LocalizedStringKey(detail))
						.font(.caption)
				}
			}
		}
		.compactWidgetTile()
	}
}

#Preview {
	ReadingCompactWidget(systemImage: "aqi.low", title: "IAQ", value: "120", detail: "Lightly Polluted", valueColor: .yellow)
}
