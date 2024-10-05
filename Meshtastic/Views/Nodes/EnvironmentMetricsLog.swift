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
				VStack {
					if chartData.count > 0 {
						GroupBox(label: Label("\(environmentMetrics.count) Readings Total", systemImage: "chart.xyaxis.line")) {
							Chart {
								ForEach(chartData, id: \.time) { dataPoint in
									AreaMark(
										x: .value("Time", dataPoint.time!),
										y: .value("Temperature", dataPoint.temperature.localeTemperature()),
										stacking: .unstacked
									)
									.interpolationMethod(.cardinal)
									.foregroundStyle(
										.linearGradient(
											colors: [.blue, .yellow, .orange, .red, .red],
											startPoint: .bottom, endPoint: .top
										)
										.opacity(0.6)
									)
									.alignsMarkStylesWithPlotArea()
									.accessibilityHidden(true)
									LineMark(
										x: .value("Time", dataPoint.time!),
										y: .value("Temperature", dataPoint.temperature.localeTemperature())
									)
									.interpolationMethod(.cardinal)
									.foregroundStyle(
										.linearGradient(
											colors: [.blue, .yellow, .orange, .red, .red],
											startPoint: .bottom, endPoint: .top
										)
									)
									.lineStyle(StrokeStyle(lineWidth: 4))
									.alignsMarkStylesWithPlotArea()
								}
							}
							.chartXAxis(content: {
								AxisMarks(position: .top)
							})
							.chartYScale(domain: format == .celsius ? -20...55 : 0...125)
							.chartForegroundStyleScale([
								"Temperature": .clear
							])
							.chartLegend(position: .automatic, alignment: .bottom)
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
}
