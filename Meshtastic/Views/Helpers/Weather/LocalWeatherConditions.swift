//
//  LocalWeatherConditions.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 7/9/24.
//
import SwiftUI
import MapKit
import WeatherKit
import OSLog

struct LocalWeatherConditions: View {
	private let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	@State var location: CLLocation?
	/// Weather
	/// The current weather condition for the city.
	@State private var condition: WeatherCondition?
	@State private var temperature: Measurement<UnitTemperature>?
	@State private var temperatureCompact: String?
	@State private var dewPoint: Measurement<UnitTemperature>?
	@State private var dewPointString: String?
	@State private var humidity: Int?
	@State private var pressure: Measurement<UnitPressure>?
	@State private var symbolName: String = "cloud.fill"
	@State private var attributionLink: URL?
	@State private var attributionLogo: URL?
	
	@Environment(\.colorScheme) var colorScheme: ColorScheme
	var body: some View {
		if location != nil {
			VStack {
				LazyVGrid(columns: gridItemLayout) {
					WeatherConditionsCompactWidget(temperature: temperatureCompact ?? "??", symbolName: symbolName, description: condition?.description.uppercased() ?? "??")
					HumidityCompactWidget(humidity: humidity ?? 0, dewPoint: temperatureCompact ?? "?")
				}
			}
			.task {
				do {
					if location != nil {
						let weather = try await WeatherService.shared.weather(for: location!)
						let numFormatter = NumberFormatter()
						let measurementFormatter = MeasurementFormatter()
						numFormatter.maximumFractionDigits = 0
						measurementFormatter.numberFormatter = numFormatter
						measurementFormatter.unitStyle = .short
						condition = weather.currentWeather.condition
						temperature = weather.currentWeather.temperature
						temperatureCompact = measurementFormatter.string(from: dewPoint ?? Measurement<UnitTemperature>(value: 0, unit: .celsius))
						dewPoint = weather.currentWeather.dewPoint
						humidity = Int(weather.currentWeather.humidity * 100)
						pressure = weather.currentWeather.pressure
						symbolName = weather.currentWeather.symbolName
						let attribution = try await WeatherService.shared.attribution
						attributionLink = attribution.legalPageURL
						attributionLogo = colorScheme == .light ? attribution.combinedMarkLightURL : attribution.combinedMarkDarkURL
					}
				} catch {
					Logger.services.error("Could not gather weather information: \(error.localizedDescription)")
					condition = .clear
					symbolName = "cloud.fill"
				}
			}
			VStack {
				HStack {
					AsyncImage(url: attributionLogo) { image in
						image
							.resizable()
							.scaledToFit()
					} placeholder: {
						ProgressView()
							.controlSize(.mini)
					}
					.frame(height: 10)
					Link("Other data sources", destination: attributionLink ?? URL(string: "https://weather-data.apple.com/legal-attribution.html")!)
						.font(.caption2)
				}
				.padding(2)
			}
		}
	}
}

struct WeatherConditionsCompactWidget: View {
	let temperature: String
	let symbolName: String
	let description: String
	var body: some View {
		ZStack(alignment: .topLeading) {
			VStack(alignment: .leading) {
				Label { Text(description) } icon: { Image(systemName: symbolName).symbolRenderingMode(.multicolor) }
					.font(.caption)
				Text(temperature)
					.font(.system(size: 90))
			}
			.frame(maxWidth: .infinity)
			.frame(height: 175)
			.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		}
	}
}

struct HumidityCompactWidget: View {
	let humidity: Int
	let dewPoint: String
	var body: some View {
		ZStack(alignment: .topLeading) {
			VStack(alignment: .leading) {
				Label { Text("HUMIDITY") } icon: { Image(systemName: "humidity").symbolRenderingMode(.multicolor) }
					.font(.caption)
				Text("\(humidity)%")
					.font(.largeTitle)
					.padding(.bottom)
				Text("The dew point is \(dewPoint) right now.")
					.lineLimit(3)
					.fixedSize(horizontal: false, vertical: true)
					.font(.caption)
			}
			.padding(.horizontal)
			.frame(maxWidth: .infinity)
			.frame(height: 175)
			.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		}
	}
}
