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

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""

	@State private var bleChartColor: Color = .blue
	@State private var wifiChartColor: Color = .orange
	@State private var paxChartColor: Color = .green
	@ObservedObject  var node: NodeInfoEntity

	var body: some View {
		VStack {
			if node.hasPax {

				let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())
				let pax = node.pax?.reversed() as? [PaxCounterEntity] ?? []
				let chartData = pax
						.filter { $0.time != nil && $0.time! >= oneWeekAgo! }
						.sorted { $0.time! < $1.time! }
				let maxValue = (chartData.map { $0.wifi }.max() ?? 0) + (chartData.map { $0.ble }.max() ?? 0) + 5
				if chartData.count > 0 {
					GroupBox(label: Label("\(pax.count) Readings Total", systemImage: "chart.xyaxis.line")) {

						Chart {
							ForEach(chartData, id: \.self) { point in
								Plot {
									PointMark(
										x: .value("x", point.time!),
										y: .value("y", (point.wifi + point.ble))
									)
								}
								.accessibilityLabel("paxcounter.total")
								.accessibilityValue("X: \(point.time!), Y: \(point.wifi + point.ble)")
								.foregroundStyle(paxChartColor)
								.interpolationMethod(.cardinal)

								Plot {
									PointMark(
										x: .value("x", point.time!),
										y: .value("y", point.wifi)
									)
								}
								.accessibilityLabel("paxcounter.wifi")
								.accessibilityValue("X: \(point.time!), Y: \(point.wifi)")
								.foregroundStyle(wifiChartColor)

								Plot {
									PointMark(
										x: .value("x", point.time!),
										y: .value("y", point.ble)
									)
								}
								.accessibilityLabel("paxcounter.ble")
								.accessibilityValue("X: \(point.time!), Y: \(point.ble)")
								.foregroundStyle(bleChartColor)
							}
						}
						.chartXAxis(content: {
							AxisMarks(position: .top)
						})
						.chartXAxis(.automatic)
						.chartYScale(domain: 0...maxValue)
						.chartForegroundStyleScale([
							"paxcounter.ble".localized: .blue,
							"paxcounter.wifi".localized: .orange,
							"paxcounter.total".localized: .green
						])
						.chartLegend(position: .automatic, alignment: .bottom)
					}
					.frame(minHeight: 250)
				}
				let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
				let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
				if UIScreen.main.bounds.size.width > 768 && (UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac) {
					// Add a table for mac and ipad
					Table(pax) {
						TableColumn("paxcounter.ble") { pc in
							Text("\(pc.ble)")
						}
						TableColumn("paxcounter.wifi") { pc in
							Text("\(pc.wifi)")
						}
						TableColumn("paxcounter.total") { pc in
							Text("\(pc.wifi + pc.ble)")
						}
						TableColumn("Uptime") { pc in
							let now = Date.now
							let later = now + TimeInterval(pc.uptime)
							let components = (now..<later).formatted(.components(style: .condensedAbbreviated))
							Text(components)
						}
						TableColumn("Timestamp") { pc in
							Text(pc.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized)
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
								Text("paxcounter.ble")
									.font(.caption)
									.fontWeight(.bold)
								Text("paxcounter.wifi")
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
							ForEach(pax) { pc in
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
									Text(pc.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized)
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
						Button("paxcounter.delete", role: .destructive) {
							if clearPax(destNum: node.num, context: context) {
								Logger.services.info("Cleared Pax Counter for \(node.num, privacy: .public)")
							} else {
								Logger.services.error("Clear Pax Counter Log Failed")
							}
						}
					}

					Button {
						exportString = paxToCsvFile(pax: pax)
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
				ContentUnavailableView("paxcounter.content.unavailable", systemImage: "slash.circle")
			}
		}
		.navigationTitle("paxcounter.log")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("paxcounter.log".localized)"),
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
}
