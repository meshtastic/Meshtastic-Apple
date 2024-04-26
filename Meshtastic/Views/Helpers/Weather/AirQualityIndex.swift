//
//  AQICircleDisplay.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2/4/23.
//
import SwiftUI

enum AqiDisplayMode: Int, CaseIterable, Identifiable {

	case pill = 0
	case dot = 1
	case text = 2
	case gauge = 3
	case gradient = 4

	var id: Int { self.rawValue }
}

struct AirQualityIndex: View {
	var aqi: Int
	var displayMode: IaqDisplayMode = .pill
	let gradient = Gradient(colors: [.green, .yellow, .orange, .red, .purple, .magenta])
	
	var body: some View {
		
		let aqiEnum = Aqi.getAqi(for: aqi)
		switch displayMode {
		case .pill:
			ZStack (alignment: .leading) {
				RoundedRectangle(cornerRadius: 10)
					.fill(aqiEnum.color)
					.frame(width: 125, height: 30)
				Label("IAQ \(aqi)", systemImage: aqi < 100 ? "aqi.low" : ((aqi > 100 && aqi < 201) ? "aqi.medium" : "aqi.high"))
					.padding(.leading, 4)
			}
		case .dot:
			VStack {
				HStack {
					Text("\(aqi)")
					Circle()
						.fill(aqiEnum.color)
						.frame(width: 10, height: 10)
				}
			}
		case .text:
			Text(aqiEnum.description)
				.font(.caption)
		case .gauge:
			Gauge(value: Double(aqi), in: 0...500) {
						
						Text("IAQ")
							.foregroundColor(aqiEnum.color)
					} currentValueLabel: {
						Text("\(Int(aqi))")
					}
					.tint(gradient)
					.gaugeStyle(.accessoryCircular)
		case .gradient:
			HStack {
				Gauge(value: Double(aqi), in: 0...500) {
							Text("IAQ")
							.foregroundColor(aqiEnum.color)
						} currentValueLabel: {
							Text("IAQ ")+Text("\(Int(aqi))")
								.foregroundColor(.gray)
						}
						.tint(gradient)
						.gaugeStyle(.accessoryLinear)
				Text(aqiEnum.description)
					.font(.caption)
			}
			.padding([.leading, .trailing])
		}
	}
}

struct AirQualityIndex_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
			Text(".pill")
				.font(.title2)
			HStack {
				AirQualityIndex(aqi: 6)
				AirQualityIndex(aqi: 51)
			}
			HStack {
				AirQualityIndex(aqi: 101)
				AirQualityIndex(aqi: 151)
			}
			HStack {
				AirQualityIndex(aqi: 201)
				AirQualityIndex(aqi: 351)
			}
			Text(".dot")
				.font(.title2)
			HStack {
				AirQualityIndex(aqi: 6, displayMode: .dot)
				AirQualityIndex(aqi: 51, displayMode: .dot)
				AirQualityIndex(aqi: 101, displayMode: .dot)
				AirQualityIndex(aqi: 201, displayMode: .dot)
				AirQualityIndex(aqi: 350, displayMode: .dot)
				AirQualityIndex(aqi: 351, displayMode: .dot)
			}
			Text(".text")
				.font(.title2)
			HStack {
				AirQualityIndex(aqi: 6, displayMode: .text)
				AirQualityIndex(aqi: 51, displayMode: .text)
				AirQualityIndex(aqi: 101, displayMode: .text)
			}
			HStack {
				AirQualityIndex(aqi: 201, displayMode: .text)
				AirQualityIndex(aqi: 350, displayMode: .text)
			}
				Text(".gauge")
				.font(.title2)
			HStack (alignment: .top) {
				AirQualityIndex(aqi: 6, displayMode: .gauge)
				AirQualityIndex(aqi: 51, displayMode: .gauge)
				AirQualityIndex(aqi: 101, displayMode: .gauge)
				AirQualityIndex(aqi: 151, displayMode: .gauge)
			}
			HStack (alignment: .top) {
				AirQualityIndex(aqi: 201, displayMode: .gauge)
				AirQualityIndex(aqi: 251, displayMode: .gauge)
				AirQualityIndex(aqi: 301, displayMode: .gauge)
				AirQualityIndex(aqi: 351, displayMode: .gauge)
			}
			HStack (alignment: .top) {
				AirQualityIndex(aqi: 401, displayMode: .gauge)
				AirQualityIndex(aqi: 500, displayMode: .gauge)
			}
			Text(".gradient")
				.font(.title2)
			AirQualityIndex(aqi: 6, displayMode: .gradient)
			AirQualityIndex(aqi: 51, displayMode: .gradient)
			AirQualityIndex(aqi: 101, displayMode: .gradient)
			AirQualityIndex(aqi: 201, displayMode: .gradient)
			AirQualityIndex(aqi: 351, displayMode: .gradient)
			AirQualityIndex(aqi: 401, displayMode: .gradient)
			AirQualityIndex(aqi: 500, displayMode: .gradient)
			
		}.previewLayout(.fixed(width: 300, height: 800))
	}
}
