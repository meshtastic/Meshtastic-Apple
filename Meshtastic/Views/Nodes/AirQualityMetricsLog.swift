//
//  AirQualityMetricsLog.swift
//  Meshtastic
//
//  Displays particulate-matter (PM) air-quality telemetry and an EPA NowCast AQI, per
//  meshtastic/design#54. When there is enough PM2.5 history a computed AQI is shown via the
//  existing AirQualityIndex view; otherwise the raw latest PM2.5 reading is shown so a
//  misleading instantaneous AQI is never displayed.
//

import Foundation
import SwiftUI
import Charts
import OSLog

struct AirQualityMetricsLog: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Bindable var node: NodeInfoEntity
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@State private var sortOrder = [KeyPathComparator(\TelemetryEntity.time, order: .reverse)]
	@State private var selection: TelemetryEntity.ID?
	@State private var chartSelection: Date?

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""

	@State private var airQualityMetrics: [TelemetryEntity] = []
	@State private var chartData: [TelemetryEntity] = []
	@State private var totalReadings = 0

	var body: some View {
		VStack {
			if totalReadings > 0 {
				// Current air quality: NowCast AQI when enough history exists, otherwise the raw
				// latest PM2.5 reading (design#54 — never show a misleading instantaneous AQI).
				GroupBox {
					if let aqi = node.currentNowCastAqi() {
						VStack(alignment: .leading, spacing: 4) {
							AirQualityIndex(aqi: aqi)
							Text("EPA NowCast AQI from PM2.5")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					} else if let pm25 = node.latestPm25 {
						VStack(alignment: .leading, spacing: 4) {
							Label("PM2.5: \(pm25) µg/m³", systemImage: "aqi.low")
							Text("Not enough recent history for a NowCast AQI yet — showing the latest raw reading.")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					}
				}
				.padding(.horizontal)

				if chartData.count > 0 {
					GroupBox(label: Label("\(totalReadings) Readings Total", systemImage: "chart.xyaxis.line")) {
						Chart {
							ForEach(chartData, id: \.self) { point in
								if let pm25 = point.pm25Standard {
									LineMark(
										x: .value("Time", point.time ?? Date()),
										y: .value("PM2.5", Double(pm25))
									)
									.foregroundStyle(by: .value("Series", "PM2.5"))
									.interpolationMethod(.linear)
									.accessibilityLabel("PM2.5")
									.accessibilityValue("X: \(point.time ?? Date()), Y: \(pm25)")
								}
								if let pm100 = point.pm100Standard {
									LineMark(
										x: .value("Time", point.time ?? Date()),
										y: .value("PM10.0", Double(pm100))
									)
									.foregroundStyle(by: .value("Series", "PM10.0"))
									.interpolationMethod(.linear)
									.accessibilityLabel("PM10.0")
									.accessibilityValue("X: \(point.time ?? Date()), Y: \(pm100)")
								}
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
						.chartForegroundStyleScale([
							"PM2.5": .orange,
							"PM10.0": .purple
						])
						.chartLegend(position: .automatic, alignment: .bottom)
					}
					.padding(.horizontal)
				}

				Table(airQualityMetrics, selection: $selection, sortOrder: $sortOrder) {
					TableColumn("PM2.5") { m in
						m.pm25Standard.map { Text("\($0) µg/m³") } ?? Text(Constants.nilValueIndicator)
					}
					.width(min: 90)
					TableColumn("PM1.0") { m in
						m.pm10Standard.map { Text("\($0) µg/m³") } ?? Text(Constants.nilValueIndicator)
					}
					.width(min: 90)
					TableColumn("PM10.0") { m in
						m.pm100Standard.map { Text("\($0) µg/m³") } ?? Text(Constants.nilValueIndicator)
					}
					.width(min: 90)
					TableColumn("Timestamp") { m in
						Text(m.time?.formatted(date: .numeric, time: .shortened) ?? "Unknown Age".localized)
					}
					.width(min: 180)
				}
				.onChange(of: selection) { _, newSelection in
					guard let metrics = airQualityMetrics.first(where: { $0.id == newSelection }) else {
						return
					}
					chartSelection = metrics.time
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
						Button("Delete Air Quality metrics?", role: .destructive) {
							Task {
								if await MeshPackets.shared.clearTelemetry(destNum: node.num, metricsType: 3) {
									Logger.data.notice("Cleared Air Quality Metrics for \(node.num, privacy: .public)")
									await MainActor.run {
										refreshMetrics()
										NotificationCenter.default.post(name: .nodeLogAvailabilityDidChange, object: node.num)
									}
								} else {
									Logger.data.error("Clear Air Quality Metrics Log Failed")
								}
							}
						}
					}

					Button {
						exportString = telemetryToCsvFile(telemetry: airQualityMetrics, metricsType: 3)
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
			} else {
				ContentUnavailableView("No Air Quality Metrics", systemImage: "slash.circle")
			}
		}
		.onAppear {
			refreshMetrics()
		}
		.onChange(of: node.lastHeard) {
			refreshMetrics()
		}
		.navigationTitle("Air Quality Metrics Log")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("Air Quality Metrics Log".localized) \(Date.now.exportTimestamp)"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Air quality metrics log download succeeded.")
				case .failure(let error):
					Logger.services.error("Air quality metrics log download failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		)
	}

	private func refreshMetrics() {
		totalReadings = node.telemetryCount(ofType: 3, context: context)
		airQualityMetrics = node.safeTelemetries(ofType: 3)
		let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
		chartData = airQualityMetrics
			.filter { ($0.time ?? Date.distantPast) >= oneWeekAgo }
			.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
	}
}
