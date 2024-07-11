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
			ZStack {
				VStack {
					HStack {
						VStack {
							VStack(alignment: .leading) {
								Text(temperatureCompact ?? "??")
									.font(.largeTitle)
								Text(condition?.description ?? "??")
									.font(.title3)
								Image(systemName: symbolName).resizable()
									.aspectRatio(contentMode: .fit)
									.frame(width: 40, height: 40)
							}
							.padding()
						}
						.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
						.frame(maxWidth: 225, maxHeight: 225)

						VStack {
							VStack(alignment: .leading) {
								Label { Text("HUMIDITY") } icon: { Image(systemName: "humidity").symbolRenderingMode(.multicolor) }
									.font(.caption)
								VStack(alignment: .leading) {
									Text("\(humidity ?? 0)%")
										.font(.largeTitle)
										.padding(.bottom)
									Text("The dew point is \(temperatureCompact ?? "?") right now.")
										.lineLimit(3)
										.fixedSize(horizontal: false, vertical: true)
										.font(.caption)
								}
							}
							.padding()
						}
						.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
						.frame(maxWidth: 225, maxHeight: 225)
					}
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
				.padding(5)
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
			.padding(5)
		}
	}
}
