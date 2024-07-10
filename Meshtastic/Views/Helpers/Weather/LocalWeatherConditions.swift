//
//  WeatherConditions.swift
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
	@State private var humidity: Int?
	@State private var symbolName: String = "cloud.fill"
	@State private var attributionLink: URL?
	@State private var attributionLogo: URL?

	@Environment(\.colorScheme) var colorScheme: ColorScheme

	var body: some View {
		if location != nil && UserDefaults.environmentEnableWeatherKit {
			VStack {
				VStack {
					Label(temperature?.formatted(.measurement(width: .narrow)) ?? "??", systemImage: symbolName)
						.font(.caption)
					Label("\(humidity ?? 0)%", systemImage: "humidity")
						.font(.caption2)
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
						condition = weather.currentWeather.condition
						temperature = weather.currentWeather.temperature
						humidity = Int(weather.currentWeather.humidity * 100)
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
			//.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.padding(5)
		}
	}
}
