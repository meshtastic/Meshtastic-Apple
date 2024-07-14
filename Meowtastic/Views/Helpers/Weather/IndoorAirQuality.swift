//
//  IndoorAirQuality.swift
//  Meshtastic
//
//  Copyright(c) by Garth Vander Houwen on 4/10/24.
//

import Foundation
import SwiftUI

enum IaqDisplayMode: Int, CaseIterable, Identifiable {

	case pill = 0
	case dot = 1
	case text = 2
	case gauge = 3
	case gradient = 4

	var id: Int { self.rawValue }
}

struct IndoorAirQuality: View {
	@State var isLegendOpen = false
	var iaq: Int = 0
	var displayMode: IaqDisplayMode = .pill
	let gradient = Gradient(colors: [.green, .mint, .yellow, .orange, .red, .purple, .purple, .brown, .brown, .brown, .brown])

	var body: some View {
		let iaqEnum = Iaq.getIaq(for: iaq)
		VStack {
			switch displayMode {
			case .pill:
				ZStack(alignment: .leading) {
					RoundedRectangle(cornerRadius: 10)
						.fill(iaqEnum.color)
						.frame(width: 125, height: 30)
					Label("IAQ \(iaq)", systemImage: iaq < 100 ? "aqi.low" : ((iaq > 100 && iaq < 201) ? "aqi.medium" : "aqi.high"))
						.padding(.leading, 4)
				}
			case .dot:
				VStack {
					HStack {
						Text("\(iaq)")
						Circle()
							.fill(iaqEnum.color)
							.frame(width: 10, height: 10)
					}
				}
			case .text:
				Text(iaqEnum.description)
					.font(.caption)
			case .gauge:
				Gauge(value: Double(iaq), in: 0...500) {
					Text("IAQ")
						.foregroundColor(iaqEnum.color)
				} currentValueLabel: {
					Text("\(Int(iaq))")
				}
				.tint(gradient)
				.gaugeStyle(.accessoryCircular)
			case .gradient:
				HStack {
					Gauge(value: Double(iaq), in: 0...500) {
						Text("IAQ")
							.foregroundColor(iaqEnum.color)
					} currentValueLabel: {
						Text("IAQ ")+Text("\(Int(iaq))")
							.foregroundColor(.gray)
					}
					.tint(gradient)
					.gaugeStyle(.accessoryLinear)
					Text(iaqEnum.description)
						.font(.caption)
				}
				.padding([.leading, .trailing])
			}
		}
		.onTapGesture {
			isLegendOpen.toggle()
		}
		.popover(isPresented: self.$isLegendOpen, arrowEdge: .bottom, content: {
			VStack(spacing: 0.5) {
				IAQScale()
			}
			.presentationCompactAdaptation(.popover)
		})
	}
}
