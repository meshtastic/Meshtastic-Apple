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
					.font(distance.length < 4 ? .system(size: 50) : .system(size: 40) )
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
	DistanceCompactWidget(distance: "123", unit: "mm")
}
