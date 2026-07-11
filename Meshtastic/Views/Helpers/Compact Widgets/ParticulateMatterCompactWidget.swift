//
//  ParticulateMatterCompactWidget.swift
//  Meshtastic
//
//  Raw particulate-matter reading tile for node detail (issue #2040 / design#54).
//

import SwiftUI

struct ParticulateMatterCompactWidget: View {
	let label: String
	let value: UInt32

	private var formattedValue: String {
		value.formatted(.number.grouping(.never))
	}

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Image(systemName: "aqi.medium")
					.font(.system(size: 30))
					.tint(.accentColor)
				Text(verbatim: label)
					.textCase(.uppercase)
					.font(.callout)
			}
			HStack(alignment: .firstTextBaseline) {
				Text(verbatim: formattedValue)
					.font(formattedValue.count < 4 ? .system(size: 50) : .system(size: 34))
				Text(verbatim: "µg/m³")
					.font(.system(size: 14))
			}
		}
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 120, idealHeight: 130, maxHeight: 140)
		.padding()
		.background(Color("Colors/MeshtasticTile"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

#Preview {
	ParticulateMatterCompactWidget(label: "PM2.5", value: 42)
}
