//
//  PowerMetricsLog.swift
//  Meshtastic
//
//  Created by Matthew Davies on 1/24/25.
//

import Foundation
import SwiftUI
import Charts
import OSLog

struct PowerMetricsLog: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@ObservedObject var node: NodeInfoEntity
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@State private var sortOrder = [KeyPathComparator(\TelemetryEntity.time, order: .reverse)]
	@State private var selection: TelemetryEntity.ID?
	@State private var chartSelection: Date?

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""

	@State private var channelSelection = 0

	var powerMetrics: [TelemetryEntity] {
		let telemetries = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 2"))
		return (telemetries?.reversed() as? [TelemetryEntity]) ?? []
	}

	var minMax: (min: Double, max: Double) {
		let allValues = powerMetrics.flatMap { [
			$0.powerCh1Voltage,
			$0.powerCh1Current,
			$0.powerCh2Voltage,
			$0.powerCh2Current,
			$0.powerCh3Voltage,
			$0.powerCh3Current
		]}

		guard !allValues.isEmpty else {
			return (min: -10, max: 10)
		}

		return (min: floor(Double(allValues.min()!)), max: ceil(Double(allValues.max()!)))
	}

	var body: some View {
		VStack {
			if node.hasPowerMetrics {
				let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())

				let chartData = powerMetrics
					.filter { $0.time != nil && $0.time! >= oneWeekAgo! }
					.sorted { $0.time! < $1.time! }
				if chartData.count > 0 {
					GroupBox(label: Label("\(powerMetrics.count) Readings Total", systemImage: "chart.xyaxis.line")) {

						// allow switching between different channels
						Picker("Select Channel", selection: $channelSelection) {
							Text("Channel 1").tag(0)
							Text("Channel 2").tag(1)
							Text("Channel 3").tag(2)
						}

						Chart {
							ForEach(chartData, id: \.self) { point in

								let voltage = channelSelection == 0 ? point.powerCh1Voltage : channelSelection == 1 ? point.powerCh2Voltage : point.powerCh3Voltage
								let current = channelSelection == 0 ? point.powerCh1Current : channelSelection == 1 ? point.powerCh2Current : point.powerCh3Current

								LineMark(
									x: .value("Time", point.time ?? Date()),
									y: .value("Voltage", voltage)
								)
								.foregroundStyle(by: .value("Series", "Voltage"))
								.interpolationMethod(.linear)
								.accessibilityLabel("Voltage")
								.accessibilityValue("X: \(point.time ?? Date()), Y: \(voltage)")

								LineMark(
									x: .value("Time", point.time ?? Date()),
									y: .value("Current", current)
								)
								.foregroundStyle(by: .value("Series", "Current"))
								.interpolationMethod(.linear)
								.accessibilityLabel("Current")
								.accessibilityValue("X: \(point.time ?? Date()), Y: \(current)")

							}

							if let chartSelection {
								RuleMark(x: .value("Second", chartSelection, unit: .second))
									.foregroundStyle(.tertiary.opacity(0.5))
							}

						}
						.chartXAxis(content: {
							AxisMarks(position: .top)
						})
						.chartXAxis(.automatic)
						.chartXSelection(value: $chartSelection)
						.chartYScale(domain: minMax.min...minMax.max)
						.chartForegroundStyleScale([
							"Voltage": .blue,
							"Current": .green
						])
						.chartLegend(position: .automatic, alignment: .bottom)
					}
				}
				let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMdjmma", options: 0, locale: Locale.current)
				let dateFormatString = (localeDateFormat ?? "M/d/YY j:mma").replacingOccurrences(of: ",", with: "")

				if idiom == .phone {
					Table(powerMetrics, selection: $selection, sortOrder: $sortOrder) {
						TableColumn("Timestamp") { powerMetrics in
							HStack {
								Text(powerMetrics.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized)
								Spacer()
								HStack {
									VStack {
										Text("Channel 1")
										HStack {
											Image(systemName: "powerplug.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											Text("\(String(format: "%.2f", powerMetrics.powerCh1Voltage))V")
										}
										HStack {
											Image(systemName: "bolt.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											Text("\(String(format: "%.2f", powerMetrics.powerCh1Current))mA")
										}
									}
								}
								Spacer()
								HStack {
									VStack {
										Text("Channel 2")
										HStack {
											Image(systemName: "powerplug.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											Text("\(String(format: "%.2f", powerMetrics.powerCh2Voltage))V")
										}
										HStack {
											Image(systemName: "bolt.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											Text("\(String(format: "%.2f", powerMetrics.powerCh2Current))mA")
										}
									}
								}
								Spacer()
								HStack {
									VStack {
										Text("Channel 3")
										HStack {
											Image(systemName: "powerplug.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											Text("\(String(format: "%.2f", powerMetrics.powerCh3Voltage))V")
										}
										HStack {
											Image(systemName: "bolt.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											Text("\(String(format: "%.2f", powerMetrics.powerCh3Current))mA")
										}
									}
								}
							}
						}
					}
					.onChange(of: selection) { _, newSelection in
						guard let metrics = powerMetrics.first(where: { $0.id == newSelection }) else {
							return
						}
						chartSelection = metrics.time
					}
				} else {
					Table(powerMetrics, selection: $selection, sortOrder: $sortOrder) {
						TableColumn("Ch1 Voltage") { dm in
							Text("\(String(format: "%.2f", dm.powerCh1Voltage))V")
						}
						.width(min: 75)
						TableColumn("Ch1 Current") { dm in
							Text("\(String(format: "%.2f", dm.powerCh1Current))mA")
						}
						.width(min: 75)
						TableColumn("Ch2 Voltage") { dm in
							Text("\(String(format: "%.2f", dm.powerCh2Voltage))V")
						}
						.width(min: 75)
						TableColumn("Ch2 Current") { dm in
							Text("\(String(format: "%.2f", dm.powerCh2Current))mA")
						}
						.width(min: 75)
						TableColumn("Ch3 Voltage") { dm in
							Text("\(String(format: "%.2f", dm.powerCh3Voltage))V")
						}
						.width(min: 75)
						TableColumn("Ch3 Current") { dm in
							Text("\(String(format: "%.2f", dm.powerCh3Current))mA")
						}
						.width(min: 75)
						TableColumn("timestamp") { dm in
							Text(dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized)
						}
						.width(min: 180)

					}
					.onChange(of: selection) { _, newSelection in
						guard let metrics = powerMetrics.first(where: { $0.id == newSelection }) else {
							return
						}
						chartSelection = metrics.time
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
					.controlSize(idiom == .phone ? .regular : .large)
					.padding(.bottom)
					.padding(.leading)
					.confirmationDialog(
						"are.you.sure",
						isPresented: $isPresentingClearLogConfirm,
						titleVisibility: .visible
					) {
						Button("power.metrics.delete", role: .destructive) {
							if clearTelemetry(destNum: node.num, metricsType: 2, context: context) {
								Logger.data.notice("Cleared Power Metrics for \(node.num)")
							} else {
								Logger.data.error("Clear Power Metrics Log Failed")
							}
						}
					}

					Button {
						exportString = telemetryToCsvFile(telemetry: powerMetrics, metricsType: 2)
						isExporting = true
					} label: {
						Label("save", systemImage: "square.and.arrow.down")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(idiom == .phone ? .regular : .large)
					.padding(.bottom)
					.padding(.trailing)
				}
				.onChange(of: selection) { _, newSelection in
					guard let metrics = powerMetrics.first(where: { $0.id == newSelection }) else {
						return
					}
					chartSelection = metrics.time
				}
			} else {
				ContentUnavailableView("No Power Metrics", systemImage: "slash.circle")
			}
		}
		.navigationTitle("power.metrics.log")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("power.metrics.log".localized)"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Power metrics log download succeeded.")
				case .failure(let error):
					Logger.services.error("Power metrics log download failed: \(error.localizedDescription)")
				}
			}
		)
	}
}
