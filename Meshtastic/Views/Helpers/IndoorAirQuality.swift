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

	var id: Int { self.rawValue }
}

struct IndoorAirQuality: View {
	var iaq: Int = 0
	var displayMode: IaqDisplayMode = .pill
	let gradient = Gradient(colors: [.green, .mint, .yellow, .orange, .red, .purple, .purple, .brown, .brown, .brown, .brown])

	var body: some View {
		let iaqEnum = Iaq.getIaq(for: iaq)
		switch displayMode {
		case .pill:
			ZStack (alignment: .leading) {
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
		}
	}
}

struct IndoorAirQuality_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
			Text(".pill")
				.font(.title)
			HStack {
				VStack{
					IndoorAirQuality(iaq: 6)
					IndoorAirQuality(iaq: 51)
					IndoorAirQuality(iaq: 101)
				}
				VStack {
					IndoorAirQuality(iaq: 201)
					IndoorAirQuality(iaq: 350)
					IndoorAirQuality(iaq: 351)
				}
			}
			Text(".dot")
				.font(.title)
			HStack {
				VStack (alignment: .leading) {
					IndoorAirQuality(iaq: 6, displayMode: .dot)
					IndoorAirQuality(iaq: 51, displayMode: .dot)
					IndoorAirQuality(iaq: 101, displayMode: .dot)
				}
				VStack (alignment: .leading) {
					IndoorAirQuality(iaq: 201, displayMode: .dot)
					IndoorAirQuality(iaq: 350, displayMode: .dot)
					IndoorAirQuality(iaq: 351, displayMode: .dot)
				}
			}
			Text(".text")
				.font(.title)
			IndoorAirQuality(iaq: 6, displayMode: .text)
			IndoorAirQuality(iaq: 51, displayMode: .text)
			IndoorAirQuality(iaq: 101, displayMode: .text)
			IndoorAirQuality(iaq: 201, displayMode: .text)
			IndoorAirQuality(iaq: 350, displayMode: .text)
			IndoorAirQuality(iaq: 351, displayMode: .text)
			Text(".gauge")
				.font(.title)
			HStack (alignment: .top) {
				VStack{
					IndoorAirQuality(iaq: 6, displayMode: .gauge)
					IndoorAirQuality(iaq: 51, displayMode: .gauge)
					IndoorAirQuality(iaq: 101, displayMode: .gauge)
					IndoorAirQuality(iaq: 151, displayMode: .gauge)
				}
				VStack{
					IndoorAirQuality(iaq: 201, displayMode: .gauge)
					IndoorAirQuality(iaq: 251, displayMode: .gauge)
					IndoorAirQuality(iaq: 301, displayMode: .gauge)
					IndoorAirQuality(iaq: 350, displayMode: .gauge)
				}
				VStack{
					IndoorAirQuality(iaq: 351, displayMode: .gauge)
					IndoorAirQuality(iaq: 401, displayMode: .gauge)
					IndoorAirQuality(iaq: 500, displayMode: .gauge)
				}
			}
		}.previewLayout(.fixed(width: 300, height: 800))
	}
}
