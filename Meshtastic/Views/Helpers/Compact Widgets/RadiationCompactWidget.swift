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
					.tint(.accentColor)
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
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 120, idealHeight: 130, maxHeight: 140)
		.padding()
		.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

#Preview {
	RadiationCompactWidget(radiation: "15", unit: "µR/hr")
}
