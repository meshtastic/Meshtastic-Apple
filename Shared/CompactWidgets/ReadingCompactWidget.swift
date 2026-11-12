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

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Image(systemName: systemImage)
					.imageScale(.small)
					.foregroundColor(.accentColor)
				Text(verbatim: title)
					.textCase(.uppercase)
					.font(.callout)
			}
			HStack {
				Text(value)
					.font(value.count < 4 ? .system(size: 50) : .system(size: 40))
					.foregroundStyle(valueColor ?? Color(uiColor: .label))
				if let unit {
					Text(unit)
						.font(.system(size: 14))
				}
			}
			if let detail {
				Text(LocalizedStringKey(detail))
					.font(.caption)
			}
		}
		.compactWidgetTile()
	}
}

#Preview {
	ReadingCompactWidget(systemImage: "aqi.low", title: "IAQ", value: "120", detail: "Lightly Polluted", valueColor: .yellow)
}
