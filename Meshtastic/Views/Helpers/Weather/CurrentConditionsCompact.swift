//
//  CurrentConditionsCompact.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2/5/23.
//
import SwiftUI

struct CurrentConditionsCompact: View {
	var temp: Float
	var condition: WeatherConditions

	var body: some View {
		Label("\(String(temp.formattedTemperature()))", systemImage: condition.symbolName)
			.font(.caption)
			.foregroundColor(.gray)
			.symbolRenderingMode(.multicolor)
	}
}
struct CurrentConditionsCompact_Previews: PreviewProvider {
	static var previews: some View {
		
		VStack {
			CurrentConditionsCompact(temp: 22, condition: WeatherConditions.clear)
			CurrentConditionsCompact(temp: 17, condition: WeatherConditions.cloudy)
			CurrentConditionsCompact(temp: -5, condition: WeatherConditions.frigid)
			CurrentConditionsCompact(temp: 38, condition: WeatherConditions.hot)
			CurrentConditionsCompact(temp: 10, condition: WeatherConditions.rain)
			CurrentConditionsCompact(temp: 30, condition: WeatherConditions.smoky)
			CurrentConditionsCompact(temp: -2, condition: WeatherConditions.snow)
		}
	}
}
