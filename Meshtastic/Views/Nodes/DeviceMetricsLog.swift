//
//  DeviceMetricsLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/7/22.
//
import SwiftUI
import Charts
import OSLog

struct DeviceMetricsLog: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""

	@State private var batteryChartColor: Color = .blue
	@State private var airtimeChartColor: Color = .yellow
	@State private var channelUtilizationChartColor: Color = .green
	@ObservedObject var node: NodeInfoEntity
	@State private var sortOrder = [KeyPathComparator(\TelemetryEntity.time, order: .reverse)]
	@State private var selection: TelemetryEntity.ID?
	@State private var chartSelection: Date?

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
								if let pointTime = point.time {
									if let batteryLevel = point.batteryLevel {
										Plot {
											LineMark(
												x: .value("x", pointTime),
												y: .value("y", batteryLevel)
											)
										}
										.accessibilityLabel("Line Series")
										.accessibilityValue("X: \(pointTime), Y: \(batteryLevel)")
										.foregroundStyle(batteryChartColor)
										.interpolationMethod(.linear)
									}
									if let channelUtilization = point.channelUtilization {
										Plot {
											PointMark(
												x: .value("x", pointTime),
												y: .value("y", channelUtilization)
											)
											.symbolSize(25)
										}
										.accessibilityLabel("Line Series")
										.accessibilityValue("X: \(pointTime), Y: \(channelUtilization)")
										.foregroundStyle(channelUtilizationChartColor)
									}
									if let chartSelection {
										RuleMark(x: .value("Second", chartSelection, unit: .second))
											.foregroundStyle(.tertiary.opacity(0.5))
									}
									if let airUtilTx = point.airUtilTx {
										Plot {
											PointMark(
												x: .value("x", pointTime),
												y: .value("y", airUtilTx)
											)
											.symbolSize(25)
										}
										.accessibilityLabel("Line Series")
										.accessibilityValue("X: \(pointTime), Y: \(airUtilTx)")
										.foregroundStyle(airtimeChartColor)
									}
								}
							}
							RuleMark(y: .value("Network Status Orange", 25))
								.lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 10]))
								.foregroundStyle(.orange)
							RuleMark(y: .value("Network Status Red", 50))
								.lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 10]))
								.foregroundStyle(.red)
						}
						.chartXAxis(content: {
							AxisMarks(position: .top)
						})
						.chartXAxis(.automatic)
						.chartXSelection(value: $chartSelection)
						.chartYScale(domain: 0...100)
						.chartForegroundStyleScale([
							idiom == .phone ? "Battery" : "Battery Level": batteryChartColor,
							"Channel Utilization": channelUtilizationChartColor,
							"Airtime": airtimeChartColor
						])
						.chartLegend(position: .automatic, alignment: .bottom)
					}
					.frame(minHeight: 240)
				}
				let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMdjmma", options: 0, locale: Locale.current)
				let dateFormatString = (localeDateFormat ?? "M/d/YY j:mma").replacingOccurrences(of: ",", with: "")
				if idiom == .phone {
					/// Single Cell Compact display for phones
					Table(deviceMetrics, selection: $selection, sortOrder: $sortOrder) {
						TableColumn("Battery Level") { dm in
							HStack {
								Text(dm.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized)
									.font(.caption)
									.fontWeight(.semibold)
								Spacer()
								Image(systemName: "bolt")
									.font(.caption)
									.symbolRenderingMode(.multicolor)
								Text("Volts \(dm.voltage?.formatted(.number.precision(.fractionLength(2))) ?? Constants.nilValueIndicator)")
									.font(.caption2)
								BatteryCompact(batteryLevel: dm.batteryLevel, font: .caption, iconFont: .callout, color: .accentColor)
							}
							HStack {
								if let channelUtilization = dm.channelUtilization {
									// Text("Channel Utilization \(String(format: "%.2f%%", channelUtilization))")
									Text("Channel Utilization \(channelUtilization.formatted(.number.precision(.fractionLength(2))))%")
										.foregroundColor(channelUtilization < 25 ? .green : (channelUtilization > 50 ? .red : .orange))
								} else {
									Text("Channel Utilization " + Constants.nilValueIndicator)
										.foregroundColor(.gray)
								}
								// Keep "Airtime" separate here as to avoid creating a new localization key
								Text("Airtime") + Text(" \(dm.airUtilTx?.formatted(.number.precision(.fractionLength(2))) ?? Constants.nilValueIndicator)%")
									.foregroundColor(.secondary)
								Spacer()
							}
							.font(.caption)
						}
						.width(ideal: 200, max: .infinity)
					}
				} else {
					/// Multi Column table for ipads and mac
					Table(deviceMetrics, selection: $selection, sortOrder: $sortOrder) {
						TableColumn("Battery Level") { dm in
							if dm.batteryLevel ?? 0 > 100 {
								Text("Powered")
							} else {
								// dm.batteryLevel.map { Text("\(String($0))%") } ?? Text("--")
								Text("\(dm.batteryLevel?.formatted(.number.precision(.fractionLength(0))) ?? Constants.nilValueIndicator)%")
							}
						}
						TableColumn("Voltage") { dm in
							// dm.voltage.map { Text("\(String(format: "%.2f", $0))") } ?? Text("--")
							Text("\(dm.voltage?.formatted(.number.precision(.fractionLength(2))) ?? Constants.nilValueIndicator)")
						}
						TableColumn("Channel Utilization") { dm in
							dm.channelUtilization.map { channelUtilization in
								// Text("\(String(format: "%.2f", channelUtilization))%")
								Text("\(channelUtilization.formatted(.number.precision(.fractionLength(2))))%")
									.foregroundColor(channelUtilization < 25 ? .green : (channelUtilization > 50 ? .red : .orange))
							} ?? Text(Constants.nilValueIndicator)
						}
						TableColumn("Airtime") { dm in
							 // dm.airUtilTx.map { Text("\(String(format: "%.2f", $0))%") } ?? Text("--")
							Text("\(dm.airUtilTx?.formatted(.number.precision(.fractionLength(2))) ?? Constants.nilValueIndicator)")
						}
						TableColumn("Uptime") { dm in
							if let uptimeSeconds = dm.uptimeSeconds {
								let now = Date.now
								let later = now + TimeInterval(uptimeSeconds)
								let components = (now..<later).formatted(.components(style: .narrow))
								Text(components)
							} else {
								Text(Constants.nilValueIndicator)
							}
						}
						.width(min: 100)
						TableColumn("Timestamp") { dm in
							Text(dm.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized)
						}
						.width(min: 180)
					}
				}
				HStack {
					Button(role: .destructive) {
						isPresentingClearLogConfirm = true
					} label: {
						Label("Clear Log", systemImage: "trash.fill")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(idiom == .phone ? .regular : .large)
					.padding(.bottom)
					.padding(.leading)
					.confirmationDialog(
						"Are you sure?",
						isPresented: $isPresentingClearLogConfirm,
						titleVisibility: .visible
					) {
						Button("Delete all device metrics?", role: .destructive) {
							Task {
								if await MeshPackets.shared.clearTelemetry(destNum: node.num, metricsType: 0) {
									Logger.data.notice("Cleared Device Metrics for \(node.num, privacy: .public)")
								} else {
									Logger.data.error("Clear Device Metrics Log Failed")
								}
							}
						}
					}

					Button {
						exportString = telemetryToCsvFile(telemetry: deviceMetrics, metricsType: 0)
						isExporting = true
					} label: {
						Label("Save", systemImage: "square.and.arrow.down")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(idiom == .phone ? .regular : .large)
					.padding(.bottom)
					.padding(.trailing)
				}
				.onChange(of: selection) { _, newSelection in
					guard let metrics = deviceMetrics.first(where: { $0.id == newSelection }) else {
						return
					}
					chartSelection = metrics.time
				}
			} else {
				ContentUnavailableView("No Device Metrics", systemImage: "slash.circle")
			}
		}
		.navigationTitle("Device Metrics Log")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
		})
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("Device Metrics Log".localized)"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Device metrics log download succeeded.")
				case .failure(let error):
					Logger.services.error("Device metrics log download failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		)
	}
}
