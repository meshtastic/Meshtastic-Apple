//
//  DistanceCompactWidget.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//

import SwiftUI

struct DistanceCompactWidget: View {
	let distance: String
	let unit: String

	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeLarge: CGFloat = 50
	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeSmall: CGFloat = 40

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Image(systemName: "ruler")
					.imageScale(.small)
					.foregroundColor(.accentColor)
				Text("Distance")
					.textCase(.uppercase)
					.font(.callout)
			}
			HStack {
				Text("\(distance)")
					.font(.system(size: distance.length < 4 ? valueSizeLarge : valueSizeSmall))
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
	DistanceCompactWidget(distance: "123", unit: "mm")
}
