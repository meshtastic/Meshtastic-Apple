//
//  DeviceMetricsLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/7/22.
//
import SwiftUI
import Charts

struct EnvironmentMetricsLog: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@State private var isPresentingClearLogConfirm: Bool = false

	@State var isExporting = false
	@State var exportString = ""

	var node: NodeInfoEntity

	var body: some View {
		
		
		let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())
		let environmentMetrics = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 1")).reversed() as? [TelemetryEntity] ?? []
		let chartData = environmentMetrics
				.filter { $0.time != nil && $0.time! >= oneWeekAgo! }
				.sorted { $0.time! < $1.time! }
		let locale = NSLocale.current as NSLocale
		let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
		var format: UnitTemperature = localeUnit as? String ?? "Celsius" == "Fahrenheit" ? .fahrenheit : .celsius
		
		NavigationStack {
			
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
						"Temperature" : .clear
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
						Text("\(String(format: "%.2f", em.relativeHumidity))%")
					}
					TableColumn("Barometric Pressure") { em in
						Text("\(String(format: "%.2f", em.barometricPressure)) hPa")
					}
					TableColumn("gas.resistance") { em in
						Text("\(String(format: "%.2f", em.gasResistance)) ohms")
					}
					TableColumn("current") { em in
						Text("\(String(format: "%.2f", em.current))")
					}
					TableColumn("voltage") { em in
						Text("\(String(format: "%.2f", em.voltage))")
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
						GridItem(.flexible(minimum: 30, maximum: 50), spacing: 0.1),
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
							Text("gas")
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
								Text("\(String(format: "%.2f", em.relativeHumidity))%")
									.font(.caption)
								Text("\(String(format: "%.2f", em.barometricPressure))")
									.font(.caption)
								Text("\(String(format: "%.2f", em.gasResistance))")
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
			.padding(.trailing)
			.confirmationDialog(
				"are.you.sure",
				isPresented: $isPresentingClearLogConfirm,
				titleVisibility: .visible
			) {
				Button("Delete all environment metrics?", role: .destructive) {
					if clearTelemetry(destNum: node.num, metricsType: 1, context: context) {
						print("Clear Environment Metrics Log Failed")
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
			.padding(.leading)
		}
		.navigationTitle("Environment Metrics Log")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			self.bleManager.context = context
		}
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") Environment Metrics Log"),
			onCompletion: { result in
				if case .success = result {
					print("Environment metrics log download succeeded.")
					self.isExporting = false
				} else {
					print("Environment metrics log download failed: \(result).")
				}
			}
		)
	}
}
