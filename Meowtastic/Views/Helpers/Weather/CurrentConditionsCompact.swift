import SwiftUI

struct CurrentConditionsCompact: View {
	var temp: Float
	var condition: WeatherConditions

	var body: some View {
		Label(temp.formattedTemperature(), systemImage: condition.symbolName)
			.font(.caption)
			.foregroundColor(.gray)
			.symbolRenderingMode(.multicolor)
	}
}
