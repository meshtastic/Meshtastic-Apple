//
//  DeviceMetricsLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/7/22.
//
import SwiftUI
import Charts
import OSLog

struct EnvironmentMetricsLog: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@State private var stops: [Gradient.Stop] = []
	@State private var chartMin: Double = 0
	@State private var chartMax: Double = 0
	@State private var chartDefaultMin: Double = 0
	@State private var chartDefaultMax: Double = 0
	@State private var chartZoomed = false
	@ObservedObject var node: NodeInfoEntity

	var body: some View {
		VStack {
			if node.hasEnvironmentMetrics {
				let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())
				let environmentMetrics = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 1")).reversed() as? [TelemetryEntity] ?? []
				let chartData = environmentMetrics
					.filter { $0.time != nil && $0.time! >= oneWeekAgo! }
					.sorted { $0.time! < $1.time! }
				let locale = NSLocale.current as NSLocale
				let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
				let format: UnitTemperature = localeUnit as? String ?? "Celsius" == "Fahrenheit" ? .fahrenheit : .celsius
				var chartLowTemp: Double = (chartData.min { a, b in a.temperature < b.temperature})?.temperature.localeTemperature() ?? chartDefaultMin
				var chartHighTemp: Double = (chartData.max { a, b in a.temperature < b.temperature})?.temperature.localeTemperature() ?? chartDefaultMax

				VStack {
					if chartData.count > 0 {
						GroupBox(label: Label("\(environmentMetrics.count) Readings Total", systemImage: "chart.xyaxis.line")) {
							Chart {
								ForEach(chartData, id: \.time) { dataPoint in
									AreaMark(
										x: .value("Time", dataPoint.time!),
										yStart: .value("Temperature", dataPoint.temperature.localeTemperature()),
										yEnd: .value("Minimum Temperature", chartLowTemp)
									)
									.interpolationMethod(.catmullRom)
									.foregroundStyle(
										.linearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
										.opacity(0.6)
									)
									.alignsMarkStylesWithPlotArea()
									.accessibilityHidden(true)
									LineMark(
										x: .value("Time", dataPoint.time!),
										y: .value("Temperature", dataPoint.temperature.localeTemperature())
									)
									.interpolationMethod(.catmullRom)
									.foregroundStyle(
										.linearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
									)
									.lineStyle(StrokeStyle(lineWidth: 4))
									.alignsMarkStylesWithPlotArea()
								}
							}
							.chartXAxis(content: {
								AxisMarks(position: .top)
							})
							.chartYScale(domain: (chartMin...chartMax)).clipped()
							.chartForegroundStyleScale([
								"Temperature": .clear
							])
							.chartLegend(position: .automatic, alignment: .bottom)
							.onTapGesture(count: 2, perform: {
								// Toggle Zoom on double tap
								updateChartRange(chartLowTemp: chartLowTemp, chartHighTemp: chartHighTemp, toggleZoom: true)
							})
							.onAppear(perform: {
								// set defaults based on C/F setting
								chartDefaultMin = (format == .celsius ? 0 : 32)
								chartDefaultMax = (format == .celsius ? 55 : 125)
								updateChartRange(chartLowTemp: chartLowTemp, chartHighTemp: chartHighTemp, toggleZoom: false)
								stops = generateStops(minTemp: chartMin, maxTemp: chartMax, tempUnit: format)
							})
							.onChange(of: node) {
								// Check for changed low/high range
								chartLowTemp = (chartData.min { a, b in a.temperature < b.temperature})?.temperature.localeTemperature() ?? chartDefaultMin
								chartHighTemp = (chartData.max { a, b in a.temperature < b.temperature})?.temperature.localeTemperature() ?? chartDefaultMax
								updateChartRange(chartLowTemp: chartLowTemp, chartHighTemp: chartHighTemp, toggleZoom: false)
								stops = generateStops(minTemp: chartMin, maxTemp: chartMax, tempUnit: format)
							}
							.onChange(of: [chartMin, chartMax]) {
								stops = generateStops(minTemp: chartMin, maxTemp: chartMax, tempUnit: format)
							}
						}
					}
					let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
					let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
					if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
						// Add a table for mac and ipad
						Table(environmentMetrics) {
							TableColumn("Temperature") { em in
								Text(em.temperature.formattedTemperature())
							}
							TableColumn("Humidity") { em in
								Text("\(String(format: "%.0f", em.relativeHumidity))%")
							}
							TableColumn("Barometric Pressure") { em in
								Text("\(String(format: "%.1f", em.barometricPressure)) hPa")
							}
							TableColumn("Indoor Air Quality") { em in
								HStack {
									Text("IAQ")
									IndoorAirQuality(iaq: Int(em.iaq), displayMode: IaqDisplayMode.dot )
								}
							}
							TableColumn("Wind Speed") { em in
								let windSpeed = Measurement(value: Double(em.windSpeed), unit: UnitSpeed.kilometersPerHour)
								Text(windSpeed.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
							}
							TableColumn("Wind Direction") { em in
								let direction = cardinalValue(from: Double(em.windDirection))
								Text(direction)
							}
							TableColumn("timestamp") { em in
								Text(em.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized)
							}
							.width(min: 180)
						}
					} else {
						ScrollView {
							let columns = [
								GridItem(.flexible(minimum: 30, maximum: 50), spacing: 0.1),
								GridItem(.flexible(minimum: 30, maximum: 60), spacing: 0.1),
								GridItem(.flexible(minimum: 30, maximum: 60), spacing: 0.1),
								GridItem(.flexible(minimum: 30, maximum: 70), spacing: 0.1),
								GridItem(spacing: 0)
							]
							LazyVGrid(columns: columns, alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {

								GridRow {
									Text("Temp")
										.font(.caption)
										.fontWeight(.bold)
									Text("Hum")
										.font(.caption)
										.fontWeight(.bold)
									Text("Bar")
										.font(.caption)
										.fontWeight(.bold)
									Text("IAQ")
										.font(.caption)
										.fontWeight(.bold)
									Text("timestamp")
										.font(.caption)
										.fontWeight(.bold)
								}
								ForEach(environmentMetrics, id: \.self) { em  in

									GridRow {

										Text(em.temperature.formattedTemperature())
											.font(.caption)
										Text("\(String(format: "%.0f", em.relativeHumidity))%")
											.font(.caption)
										Text("\(String(format: "%.1f", em.barometricPressure))")
											.font(.caption)
										IndoorAirQuality(iaq: Int(em.iaq), displayMode: .dot)
											.font(.caption)
										Text(em.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized)
											.font(.caption)
									}
								}
							}
							.padding(.leading, 15)
							.padding(.trailing, 5)
						}
					}
				}
				HStack {

					Button(role: .destructive) {
						isPresentingClearLogConfirm = true
					} label: {
						Label("clear.log", systemImage: "trash.fill")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.bottom)
					.padding(.leading)
					.confirmationDialog(
						"are.you.sure",
						isPresented: $isPresentingClearLogConfirm,
						titleVisibility: .visible
					) {
						Button("Delete all environment metrics?", role: .destructive) {
							if clearTelemetry(destNum: node.num, metricsType: 1, context: context) {
								Logger.services.error("Clear Environment Metrics Log Failed")
							}
						}
					}
					Button {
						exportString = telemetryToCsvFile(telemetry: environmentMetrics, metricsType: 1)
						isExporting = true
					} label: {
						Label("save", systemImage: "square.and.arrow.down")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.bottom)
					.padding(.trailing)
				}

			} else {
				ContentUnavailableView("No Environment Metrics", systemImage: "slash.circle")
			}
		}

		.navigationTitle("Environment Metrics Log")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") Environment Metrics Log"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Environment metrics log download succeeded.")
				case .failure(let error):
					Logger.services.error("Environment metrics log download failed: \(error.localizedDescription)")
				}
			}
		)
	}

	// Set and optionally adjust the chart min/max
	func updateChartRange(chartLowTemp: Double, chartHighTemp: Double, toggleZoom: Bool) {
		if toggleZoom {
			chartZoomed.toggle()
		}
		if chartZoomed {
			// Use the low and high temp for the bounds
			chartMin = chartLowTemp - Double(5.0)
			chartMax = chartHighTemp + Double(5.0)
		} else {
			// Use the default low and high bounds, adjust if the high or low land outside the
			// default min/max
			chartMin = (chartLowTemp < chartDefaultMin ? chartLowTemp : chartDefaultMin) - Double(5.0)
			chartMax = (chartHighTemp > chartDefaultMax ? chartHighTemp : chartDefaultMax) + Double(5.0)
		}
		return
	}
}

// Set up gradient stops relative to the scale of the temperature chart
func generateStops(minTemp: Double, maxTemp: Double, tempUnit: UnitTemperature) -> [Gradient.Stop] {
	var gradientStops = [Gradient.Stop]()

	let stopTargets: [(Double, Color)] = [
		((tempUnit == .celsius ? 0 : 32), .blue),
		((tempUnit == .celsius ? 20 : 68), .yellow),
		((tempUnit == .celsius ? 30 : 86), .orange),
		((tempUnit == .celsius ? 55 : 125), .red)
		]
	for (stopValue, color) in stopTargets {
		let stopLocation = transform(stopValue, from: minTemp...maxTemp, to: 0...1)
		gradientStops.append(Gradient.Stop(color: color, location: stopLocation))
	}
	return gradientStops
}

// Map inputRange to outputRange
func transform<T: FloatingPoint>(_ input: T, from inputRange: ClosedRange<T>, to outputRange: ClosedRange<T>) -> T {
	// need to determine what that value would be in (to.low, to.high)
	// difference in output range / difference in input range = slope
	let slope = (outputRange.upperBound - outputRange.lowerBound) / (inputRange.upperBound - inputRange.lowerBound)
	// slope * normalized input + output lower
	let output = slope * (input - inputRange.lowerBound) + outputRange.lowerBound
	return output
}
