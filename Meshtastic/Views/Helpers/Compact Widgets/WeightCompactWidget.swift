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

	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeLarge: CGFloat = 50
	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeSmall: CGFloat = 40

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
					.font(.system(size: weight.length < 4 ? valueSizeLarge : valueSizeSmall))
					.lineLimit(1)
					.minimumScaleFactor(0.5)
				Text(unit)
					.font(.footnote)
			}
		}
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 120, idealHeight: 130, maxHeight: 140)
		.padding()
		.background(Color("Colors/MeshtasticTile"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

#Preview {
    WeightCompactWidget(weight: "123", unit: "kg")
}
