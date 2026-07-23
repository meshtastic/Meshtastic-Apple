//
//  PaxCounterLog.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 2/25/24.
//

import SwiftUI
import Charts
import OSLog

struct PaxCounterLog: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""

	@State private var bleChartColor: Color = .blue
	@State private var wifiChartColor: Color = .orange
	@State private var paxChartColor: Color = .green
	@Bindable  var node: NodeInfoEntity
	@State private var paxCounters: [PaxCounterEntity] = []
	@State private var chartData: [PaxCounterEntity] = []
	@State private var maxValue: Int32 = 5
	@State private var totalReadings = 0

	@ViewBuilder
	private func paxChart(chartData: [PaxCounterEntity], maxValue: Int32) -> some View {
		Chart {
			ForEach(chartData, id: \.self) { point in
				if let pointTime = point.time {
					Plot {
						PointMark(
							x: .value("x", pointTime),
							y: .value("y", (point.wifi + point.ble))
						)
					}
					.accessibilityLabel(String(localized: "Total PAX at \(pointTime.formatted(date: .abbreviated, time: .shortened))", comment: "VoiceOver label for a total PAX point on the PAX counter chart. %@ is the timestamp."))
					.accessibilityValue(String(localized: "\((point.wifi + point.ble).formatted()) devices", comment: "VoiceOver value spoken as a device count on the PAX counter chart. %@ is the number."))
					.foregroundStyle(paxChartColor)
					.interpolationMethod(.cardinal)

					Plot {
						PointMark(
							x: .value("x", pointTime),
							y: .value("y", point.wifi)
						)
					}
					.accessibilityLabel(String(localized: "Wi-Fi devices at \(pointTime.formatted(date: .abbreviated, time: .shortened))", comment: "VoiceOver label for a Wi-Fi device-count point on the PAX counter chart. %@ is the timestamp."))
					.accessibilityValue(String(localized: "\(point.wifi.formatted()) devices", comment: "VoiceOver value spoken as a device count on the PAX counter chart. %@ is the number."))
					.foregroundStyle(wifiChartColor)

					Plot {
						PointMark(
							x: .value("x", pointTime),
							y: .value("y", point.ble)
						)
					}
					.accessibilityLabel(String(localized: "BLE devices at \(pointTime.formatted(date: .abbreviated, time: .shortened))", comment: "VoiceOver label for a BLE device-count point on the PAX counter chart. %@ is the timestamp."))
					.accessibilityValue(String(localized: "\(point.ble.formatted()) devices", comment: "VoiceOver value spoken as a device count on the PAX counter chart. %@ is the number."))
					.foregroundStyle(bleChartColor)
				}
			}
		}
		.chartXAxis(content: {
			AxisMarks(position: .top)
		})
		.chartXAxis(.automatic)
		.chartYScale(domain: 0...maxValue)
		.chartForegroundStyleScale([
			"BLE".localized: .blue,
			"WiFi".localized: .orange,
			"Total PAX".localized: .green
		])
		.chartLegend(position: .automatic, alignment: .bottom)
	}

	var body: some View {
		VStack {
			if totalReadings > 0 {
				if chartData.count > 0 {
					GroupBox(label: Label("\(totalReadings) Readings Total", systemImage: "chart.xyaxis.line")) {
						paxChart(chartData: chartData, maxValue: maxValue)
					}
					.frame(minHeight: 250)
				}
				if UIScreen.main.bounds.size.width > 768 && (UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac) {
					// Add a table for mac and ipad
					Table(paxCounters) {
						TableColumn("BLE") { pc in
							Text("\(pc.ble)")
						}
						TableColumn("WiFi") { pc in
							Text("\(pc.wifi)")
						}
						TableColumn("Total PAX") { pc in
							Text("\(pc.wifi + pc.ble)")
						}
						TableColumn("Uptime") { pc in
							let now = Date.now
							let later = now + TimeInterval(pc.uptime)
							let components = (now..<later).formatted(.components(style: .condensedAbbreviated))
							Text(components)
						}
						TableColumn("Timestamp") { pc in
							Text(pc.time?.formatted(date: .numeric, time: .shortened) ?? "Unknown Age".localized)
						}
						.width(min: 180)
					}
				} else {
					ScrollView {
						let columns = [
							GridItem(.flexible(minimum: 20, maximum: 50), spacing: 0.1),
							GridItem(.flexible(minimum: 20, maximum: 50), spacing: 0.1),
							GridItem(.flexible(minimum: 20, maximum: 50), spacing: 0.1),
							GridItem(.flexible(minimum: 60, maximum: 140), spacing: 0.1),
							GridItem(.flexible(minimum: 100, maximum: 160), spacing: 0.1)
						]
						LazyVGrid(columns: columns, alignment: .leading, spacing: 1) {
							GridRow {
								Text("BLE")
									.font(.caption)
									.fontWeight(.bold)
								Text("WiFi")
									.font(.caption)
									.fontWeight(.bold)
								Text("Total")
									.font(.caption)
									.fontWeight(.bold)
								Text("Uptime")
									.font(.caption)
									.fontWeight(.bold)
								Text("Timestamp")
									.font(.caption)
									.fontWeight(.bold)
							}
							ForEach(paxCounters) { pc in
								GridRow {
									Text(String(pc.ble))
										.font(.caption)
									Text(String(pc.wifi))
										.font(.caption)
									Text(String(pc.ble + pc.wifi))
										.font(.caption)
									let now = Date.now
									let later = now + TimeInterval(pc.uptime)
									let components = (now..<later).formatted(.components(style: .condensedAbbreviated))
									Text(components)
										.font(.caption)
									Text(pc.time?.formatted(date: .numeric, time: .shortened) ?? "Unknown Age".localized)
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
							Label("Clear", systemImage: "trash.fill")
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.padding(.bottom)
						.padding(.leading)
						.confirmationDialog(
							"Are you sure?",
							isPresented: $isPresentingClearLogConfirm,
							titleVisibility: .visible
						) {
							Button("Delete all pax data?", role: .destructive) {
								Task {
									if await MeshPackets.shared.clearPax(destNum: node.num) {
										Logger.services.info("Cleared Pax Counter for \(node.num, privacy: .public)")
										await MainActor.run {
											refreshPaxCounters()
											NotificationCenter.default.post(name: .nodeLogAvailabilityDidChange, object: node.num)
										}
									} else {
										Logger.services.error("Clear Pax Counter Log Failed")
									}
								}
							}
						}

						Button {
							exportString = paxToCsvFile(pax: node.paxCountersSortedByTime(context: context, ascending: true))
							isExporting = true
						} label: {
							Label("Save", systemImage: "square.and.arrow.down")
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.padding(.bottom)
						.padding(.trailing)
					}
				} else {
					ContentUnavailableView("No PAX Counter Logs", systemImage: "slash.circle")
				}
			}
	.onAppear {
		refreshPaxCounters()
	}
	.onChange(of: node.lastHeard) {
		refreshPaxCounters()
	}
		.navigationTitle("PAX Counter Log")
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
			defaultFilename: String("\(node.user?.longName ?? "Node") \("paxcounter.log".localized) \(Date.now.exportTimestamp)"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("PAX Counter log download succeeded")
				case .failure(let error):
					Logger.services.error("PAX Counter log download failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		)
	}

	private func refreshPaxCounters() {
		totalReadings = node.paxCount(context: context)
		paxCounters = node.paxCountersSortedByTime(context: context, ascending: false, limit: 500)
		let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
		chartData = paxCounters
			.filter { ($0.time ?? Date.distantPast) >= oneWeekAgo }
			.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
		maxValue = (chartData.map { $0.wifi }.max() ?? 0) + (chartData.map { $0.ble }.max() ?? 0) + 5
	}
}

// TODO: Fix preview for SwiftData
/*
#Preview {
	let node = NodeInfoEntity()
	node.num = 123456789
	let user = UserEntity()
	user.longName = "Test Node"
	user.shortName = "TN"
	node.user = user
	PaxCounterLog(node: node)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
*/
