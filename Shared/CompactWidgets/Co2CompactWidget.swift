//
//  Co2CompactWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//

import SwiftUI

/// CO2 reading tile for node detail, with its design#53 band.
struct Co2CompactWidget: View {
	let ppm: UInt32

	private var level: Co2Level { Co2Level.level(for: ppm) }

	private var formattedValue: String {
		ppm.formatted(.number.grouping(.never))
	}

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Image(systemName: "carbon.dioxide.cloud")
					.font(.system(size: 30))
				Text(verbatim: "CO2")
					.font(.callout)
			}
			HStack(alignment: .firstTextBaseline) {
				Text(verbatim: formattedValue)
					.font(formattedValue.count < 4 ? .system(size: 50) : .system(size: 34))
				Text(verbatim: "ppm")
					.font(.system(size: 14))
			}
			HStack(spacing: 4) {
				Circle()
					.fill(level.color)
					.frame(width: 8, height: 8)
					.accessibilityHidden(true)
				Text(level.description)
					.font(.caption)
			}
		}
		.compactWidgetTile()
	}
}

#Preview {
	Co2CompactWidget(ppm: 1240)
}
