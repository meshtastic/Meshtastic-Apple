import SwiftUI
import MapKit
#if canImport(WeatherKit)
@preconcurrency import WeatherKit
#endif
import OSLog

@available(iOS 16, *)
struct LocalWeatherConditions: View {
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
			GeometryReader { geometry in
				VStack(alignment: .center) {
					// Determine the number of columns based on the screen width
					let columns = geometry.size.width > 600 ? 4 : 2
					let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 20), count: columns)

					LazyVGrid(columns: gridItemLayout) {
						WeatherConditionsCompactWidget(temperature: temperature, symbolName: symbolName, description: condition?.description.uppercased() ?? "??")
							.padding(.bottom, columns == 2 ? 10 : 0)
						HumidityCompactWidget(humidity: humidity ?? 0, dewPoint: dewPoint)
							.padding(.bottom, columns == 2 ? 10 : 0)
						PressureCompactWidget(pressure: String(pressure?.value ?? 0.0 / 100), unit: pressure?.unit.symbol ?? "??", low: pressure?.value ?? 0.0 <= 1009.144)
						WindCompactWidget(speed: windSpeed, gust: windGust, direction: windCompassDirection)
					}
					
					HStack {
						AsyncImage(url: attributionLogo) { image in
							image
								.resizable()
								.scaledToFit()
							    .frame(height: 10)
						} placeholder: {
							ProgressView()
								.controlSize(.mini)
						}
						Link("Other data sources", destination: attributionLink ?? URL(string: "https://weather-data.apple.com/legal-attribution.html")!)
							.font(.caption2)
					}
					.offset(y: -2)
					.padding(.bottom, -15)
				}
				.background(
					// Use GeometryReader here to get the VGrid's height
					GeometryReader { proxy in
						// Set the preference key with the VGrid's height
						Color.clear.preference(key: WeatherKitTilesHeightKey.self, value: proxy.size.height)
					}
				)
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
					Logger.services.error("Could not gather weather information: \(error.localizedDescription, privacy: .public)")
					condition = .clear
					symbolName = "cloud.fill"
				}
			}
		}
	}
}

/// Magnus Formula
func calculateDewPoint(temp: Float, relativeHumidity: Float, convertToLocale: Bool = true) -> Double {
	let a: Float = 17.27
	let b: Float = 237.7
	let alpha = ((a * temp) / (b + temp)) + log(relativeHumidity / 100.0)
	let dewPoint = (b * alpha) / (a - alpha)
	let dewPointUnit = Measurement<UnitTemperature>(value: Double(dewPoint), unit: .celsius)
	
	if !convertToLocale {
		return Double(dewPoint)
	}
	
	// Otherwise convert to locale units, default behavior
	let locale = NSLocale.current as NSLocale
	let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
	var format: UnitTemperature = .celsius

	if localeUnit! as? String == "Fahrenheit" {
		format = .fahrenheit
	}
	return dewPointUnit.converted(to: format).value
}
