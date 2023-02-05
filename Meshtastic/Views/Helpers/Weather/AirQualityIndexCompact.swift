//
//  AQICircleDisplay.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2/4/23.
//
import SwiftUI

struct AirQualityIndexCompact: View {
	var aqi: Int

	var body: some View {
		

		HStack (spacing: 0.5) {
			Text("AQI \(aqi)")
				.foregroundColor(.gray)
				.padding(.trailing, 0)
				.font(.caption)
			
			if aqi > 0 && aqi < 51 {
				// Good
				Circle()
					.fill(.green)
					.frame(width: 10, height: 10)
			} else if aqi > 50 && aqi < 101 {
				// Satisfactory
				Circle()
					.fill(Color(red: 0, green: 0.9882, blue: 0.1804))
					.frame(width: 10, height: 10)
			} else if aqi > 100 && aqi < 201 {
				// Moderate
				Circle()
					.fill(.yellow)
					.frame(width: 10, height: 10)
			} else if aqi > 200 && aqi < 301 {
				// Poor
				Circle()
					.fill(.orange)
					.frame(width: 10, height: 10)
					
			} else if aqi > 300 && aqi < 401 {
				// Very Poor
				Circle()
					.fill(.red)
					.frame(width: 10, height: 10)
			} else if aqi >= 401 {
				// Very Poor
				Circle()
					.fill(Color(red: 0.8392, green: 0.0667, blue: 0))
					.frame(width: 10, height: 10)
			}
		}
	}
}
struct AQICircleDisplay_Previews: PreviewProvider {
	static var previews: some View {
		
		VStack {
			AirQualityIndexCompact(aqi: 5)
			AirQualityIndexCompact(aqi: 51)
			AirQualityIndexCompact(aqi: 101)
			AirQualityIndexCompact(aqi: 201)
			AirQualityIndexCompact(aqi: 301)
			AirQualityIndexCompact(aqi: 401)
		}
	}
}
