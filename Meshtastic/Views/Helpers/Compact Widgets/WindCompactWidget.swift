//
//  WindCompactWidget.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//
import SwiftUI

struct WindCompactWidget: View {
	let speed: String
	let gust: String?
	let direction: String?

	var body: some View {
		let hasGust = ((gust ?? "").isEmpty == false)
		VStack(alignment: .leading) {
			Label { Text("Wind").textCase(.uppercase) } icon: { Image(systemName: "wind").foregroundColor(.accentColor) }
			if let direction {
				Text("\(direction)")
					.font(!hasGust ? .callout : .caption)
					.padding(.bottom, 10)
			}
			Text(speed)
				.font(.system(size: 35))
			if let gust, !gust.isEmpty {
				Text("Gusts \(gust)")
			}
		}
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 120, idealHeight: 130, maxHeight: 140)
		.padding()
		.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

#Preview {
	let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	Form {
		LazyVGrid(columns: gridItemLayout) {
			WindCompactWidget(speed: "12 mph", gust: "15 mph", direction: "SW")
			WindCompactWidget(speed: "12 mph", gust: nil, direction: "SW")
			WindCompactWidget(speed: "12 mph", gust: "15 mph", direction: nil)
			WindCompactWidget(speed: "12 mph", gust: nil, direction: nil)
		}
	}
}
