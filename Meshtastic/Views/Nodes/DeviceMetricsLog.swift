//
//  DeviceMetricsLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/7/22.
//
import SwiftUI
import Charts

struct DeviceMetricsLog: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""

	@State private var batteryChartColor: Color = .blue
	@State private var airtimeChartColor: Color = .orange
	@State private var channelUtilizationChartColor: Color = .green
	@ObservedObject  var node: NodeInfoEntity

	var body: some View {
		VStack {
			if node.hasDeviceMetrics {
				let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())
				let deviceMetrics = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0")).reversed() as? [TelemetryEntity] ?? []
				let chartData = deviceMetrics
						.filter { $0.time != nil && $0.time! >= oneWeekAgo! }
						.sorted { $0.time! < $1.time! }
				if chartData.count > 0 {
					GroupBox(label: Label("\(deviceMetrics.count) Readings Total", systemImage: "chart.xyaxis.line")) {

						Chart {
							ForEach(chartData, id: \.self) { point in
								Plot {
									LineMark(
										x: .value("x", point.time!),
										y: .value("y", point.batteryLevel)
									)
								}
								.accessibilityLabel("Line Series")
								.accessibilityValue("X: \(point.time!), Y: \(point.batteryLevel)")
								.foregroundStyle(batteryChartColor)
								.interpolationMethod(.linear)

								Plot {
									PointMark(
										x: .value("x", point.time!),
										y: .value("y", point.channelUtilization)
									)
									.symbolSize(25)
								}
								.accessibilityLabel("Line Series")
								.accessibilityValue("X: \(point.time!), Y: \(point.channelUtilization)")
								.foregroundStyle(channelUtilizationChartColor)

								RuleMark(y: .value("Limit", 10))
									.lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 10]))
									.foregroundStyle(airtimeChartColor)

								Plot {
									PointMark(
										x: .value("x", point.time!),
										y: .value("y", point.airUtilTx)
									)
									.symbolSize(25)
								}
								.accessibilityLabel("Line Series")
								.accessibilityValue("X: \(point.time!), Y: \(point.airUtilTx)")
								.foregroundStyle(airtimeChartColor)
							}
						}
						.chartXAxis(content: {
							AxisMarks(position: .top)
						})
						.chartXAxis(.automatic)
						.chartYScale(domain: 0...100)
						.chartForegroundStyleScale([
							"Battery Level": .blue,
							"Channel Utilization": .green,
							"Airtime": .orange
						])
						.chartLegend(position: .automatic, alignment: .bottom)
					}
					.frame(minHeight: 250)
				}
				let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
				let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
				if UIScreen.main.bounds.size.width > 768 && (UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac) {
					// Add a table for mac and ipad
					// Table(Array(deviceMetrics),id: \.self) {
					Table(deviceMetrics) {
						TableColumn("battery.level") { dm in
							if dm.batteryLevel > 100 {
								Text("Powered")
							} else {
								Text("\(String(dm.batteryLevel))%")
							}
						}
						TableColumn("voltage") { dm in
							Text("\(String(format: "%.2f", dm.voltage))")
						}
						TableColumn("channel.utilization") { dm in
							Text("\(String(format: "%.2f", dm.channelUtilization))%")
						}
						TableColumn("airtime") { dm in
							Text("\(String(format: "%.2f", dm.airUtilTx))%")
						}
						TableColumn("uptime") { dm in
							let now = Date.now
							let later = now + TimeInterval(dm.uptimeSeconds)
							let components = (now..<later).formatted(.components(style: .condensedAbbreviated))
							Text(components)
						}
						TableColumn("timestamp") { dm in
							Text(dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized)
						}
						.width(min: 180)
					}
				} else {
					ScrollView {
						let columns = [
							GridItem(.flexible(minimum: 25, maximum: 45), spacing: 0.1),
							GridItem(.flexible(minimum: 25, maximum: 50), spacing: 0.1),
							GridItem(.flexible(minimum: 30, maximum: 65), spacing: 0.1),
							GridItem(.flexible(minimum: 30, maximum: 65), spacing: 0.1),
							GridItem(.flexible(minimum: 30, maximum: 60), spacing: 0.1),
							GridItem(.flexible(minimum: 130, maximum: 200), spacing: 0.1)
						]
						LazyVGrid(columns: columns, alignment: .leading, spacing: 1) {
							GridRow {
								Text("Batt")
									.font(.caption)
									.fontWeight(.bold)
								Text("Volt")
									.font(.caption)
									.fontWeight(.bold)
								Text("ChUtil")
									.font(.caption)
									.fontWeight(.bold)
								Text("AirTm")
									.font(.caption)
									.fontWeight(.bold)
								Text("uptime")
									.font(.caption)
									.fontWeight(.bold)
								Text("timestamp")
									.font(.caption)
									.fontWeight(.bold)
							}
							ForEach(deviceMetrics) { dm in
								GridRow {
									if dm.batteryLevel > 100 {
										Text("PWD")
											.font(.caption)
									} else {
										Text("\(String(dm.batteryLevel))%")
											.font(.caption)
									}
									Text(String(dm.voltage))
										.font(.caption)
									Text("\(String(format: "%.2f", dm.channelUtilization))%")
										.font(.caption)
									Text("\(String(format: "%.2f", dm.airUtilTx))%")
										.font(.caption)
									let now = Date.now
									let later = now + TimeInterval(dm.uptimeSeconds)
									let components = (now..<later).formatted(.components(style: .condensedAbbreviated))
									Text(components)
										.font(.caption)
									Text(dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized)
										.font(.caption)
								}
							}
						}
						.padding(.leading, 15)
						.padding(.trailing, 5)
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
						Button("device.metrics.delete", role: .destructive) {
							if clearTelemetry(destNum: node.num, metricsType: 0, context: context) {
								print("Cleared Device Metrics for \(node.num)")
							} else {
								print("Clear Device Metrics Log Failed")
							}
						}
					}

					Button {
						exportString = telemetryToCsvFile(telemetry: deviceMetrics, metricsType: 0)
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
				if #available (iOS 17, *) {
					ContentUnavailableView("No Device Metrics", systemImage: "slash.circle")
				} else {
					Text("No Device Metrics")
				}
			}
		}
		.navigationTitle("device.metrics.log")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
		}
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("device.metrics.log".localized)"),
			onCompletion: { result in
				if case .success = result {
					print("Device metrics log download succeeded.")
					self.isExporting = false
				} else {
					print("Device metrics log download failed: \(result).")
				}
			}
		)
	}
}
