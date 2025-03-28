//
//  WeightCompactWidget.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//

import SwiftUI

struct WeightCompactWidget: View {
	let weight: String
	let unit: String

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Image(systemName: "scalemass")
					.imageScale(.small)
					.foregroundColor(.accentColor)
				Text("Weight")
					.textCase(.uppercase)
					.font(.callout)
			}
			HStack {
				Text("\(weight)")
					.font(weight.length < 4 ? .system(size: 50) : .system(size: 40) )
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
    WeightCompactWidget(weight: "123", unit: "kg")
}
