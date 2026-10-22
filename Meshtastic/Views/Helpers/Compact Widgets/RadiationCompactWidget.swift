//
//  RadiationCompactWidget.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//

import SwiftUI

struct RadiationCompactWidget: View {
	let radiation: String
	let unit: String

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Text(verbatim: "☢")
					.font(.system(size: 30, design: .monospaced))
				Text("Radiation")
					.textCase(.uppercase)
					.font(.callout)
			}
			HStack {
				Text("\(radiation)")
					.font(radiation.length < 4 ? .system(size: 50) : .system(size: 34) )
				Text(unit)
					.font(.system(size: 14))
			}
		}
		.compactWidgetTile()
	}
}

#Preview {
	RadiationCompactWidget(radiation: "15", unit: "µR/hr")
}
