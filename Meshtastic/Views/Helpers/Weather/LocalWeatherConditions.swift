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
	@State private var temperature: String = ""
	@State private var dewPoint: String = ""
	@State private var humidity: Int?
	@State private var pressure: Measurement<UnitPressure>?
	@State private var windSpeed: String = ""
	@State private var windGust: String = ""
	@State private var windDirection: Measurement<UnitAngle>?
	@State private var windCompassDirection: String = ""
	@State private var symbolName: String = "cloud.fill"
	@State private var attributionLink: URL?
	@State private var attributionLogo: URL?

	@Environment(\.colorScheme) var colorScheme: ColorScheme
	var body: some View {
		if location != nil {
			VStack {
				LazyVGrid(columns: gridItemLayout) {
					WeatherConditionsCompactWidget(temperature: temperature, symbolName: symbolName, description: condition?.description.uppercased() ?? "??")
					HumidityCompactWidget(humidity: humidity ?? 0, dewPoint: dewPoint)
					PressureCompactWidget(pressure: String(pressure?.value ?? 0.0 / 100), unit: pressure?.unit.symbol ?? "??", low: pressure?.value ?? 0.0 <= 1009.144)
					WindCompactWidget(speed: windSpeed, gust: windGust, direction: windCompassDirection)
				}
			}
			.padding(.top)
			.task {
				do {
					if location != nil {
						let weather = try await WeatherService.shared.weather(for: location!)
						let numFormatter = NumberFormatter()
						let measurementFormatter = MeasurementFormatter()
						numFormatter.maximumFractionDigits = 0
						measurementFormatter.numberFormatter = numFormatter
						measurementFormatter.unitStyle = .short
						measurementFormatter.locale = Locale.current
						condition = weather.currentWeather.condition
						temperature = measurementFormatter.string(from: weather.currentWeather.temperature)
						dewPoint = measurementFormatter.string(from: weather.currentWeather.dewPoint)
						humidity = Int(weather.currentWeather.humidity * 100)
						pressure = weather.currentWeather.pressure
						windSpeed = measurementFormatter.string(from: weather.currentWeather.wind.speed)
						windGust = measurementFormatter.string(from: weather.currentWeather.wind.gust ?? Measurement(value: 0.0, unit: weather.currentWeather.wind.gust!.unit))
						windDirection = weather.currentWeather.wind.direction
						windCompassDirection = weather.currentWeather.wind.compassDirection.description
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
		VStack(alignment: .leading) {
			Label { Text(description) } icon: { Image(systemName: symbolName).symbolRenderingMode(.multicolor) }
				.font(.caption)
			Text(temperature)
				.font(temperature.length < 4 ? .system(size: 80) : .system(size: 60) )
		}
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 130, idealHeight: 140, maxHeight: 150)
		.padding()
		.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

struct HumidityCompactWidget: View {
	let humidity: Int
	let dewPoint: String
	var body: some View {
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
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 130, idealHeight: 140, maxHeight: 150)
		.padding()
		.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

struct PressureCompactWidget: View {
	let pressure: String
	let unit: String
	let low: Bool
	var body: some View {
		VStack(alignment: .leading) {
			Label { Text("PRESSURE") } icon: { Image(systemName: "gauge").symbolRenderingMode(.multicolor) }
				.font(.caption)
			Text(pressure)
				.font(pressure.length < 7 ? .system(size: 35) : .system(size: 30) )
			Text(low ? "LOW" : "HIGH")
				.padding(.bottom)
			Text(unit)
		}
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 130, idealHeight: 140, maxHeight: 150)
		.padding()
		.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

struct WindCompactWidget: View {
	let speed: String
	let gust: String
	let direction: String
	var body: some View {
		VStack(alignment: .leading) {
			Label { Text("WIND") } icon: { Image(systemName: "wind").foregroundColor(.accentColor) }
			Text("\(direction)")
				.font(gust.isEmpty ? .callout : .caption)
				.padding(.bottom, 10)
			Text(speed)
				.font(gust.isEmpty ? .system(size: 45) : .system(size: 35))
			if !gust.isEmpty {
				Text("Gusts \(gust)")
			}
		}
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 130, idealHeight: 140, maxHeight: 150)
		.padding()
		.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

/// Magnus Formula
func calculateDewPoint(temp: Float, relativeHumidity: Float) -> Double {
	let a: Float = 17.27
	let b: Float = 237.7
	let alpha = ((a * temp) / (b + temp)) + log(relativeHumidity / 100.0)
	let dewPoint = (b * alpha) / (a - alpha)
	let dewPointUnit = Measurement<UnitTemperature>(value: Double(dewPoint), unit: .celsius)
	let locale = NSLocale.current as NSLocale
	let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
	var format: UnitTemperature = .celsius

	if localeUnit! as? String == "Fahrenheit" {
		format = .fahrenheit
	}
	return dewPointUnit.converted(to: format).value
}
