//
//  DetectionSensorLog.swift
//  Meshtastic
//
//  Created by Ben on 8/22/23.
//

import SwiftUI
import SwiftData
import Charts
import MeshtasticProtobufs
import OSLog

struct DetectionSensorLog: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@Bindable var node: NodeInfoEntity
	@Query(filter: #Predicate<MessageEntity> { $0.portNum == 10 },
		   sort: \MessageEntity.messageTimestamp, order: .reverse)
	private var detections: [MessageEntity]

	var body: some View {
		let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())
		let chartData = detections
			.filter { $0.timestamp >= oneDayAgo! && $0.fromUser?.num ?? -1 == node.user?.num ?? 0 }
			.sorted { $0.timestamp < $1.timestamp }

		VStack {
			if chartData.count > 0 {
				GroupBox(label: Label("\(chartData.count) Total Detection Events", systemImage: "sensor")) {
					Chart {
						ForEach(chartData, id: \.self) { point in
							Plot {
								BarMark(
									x: .value("x", point.timestamp, unit: .hour),
									y: .value("y", 1)
								)
							}
							.accessibilityLabel("Bar Series")
							.accessibilityValue("X: \(point.timestamp), Y: \(1)")
							.interpolationMethod(.cardinal)
							.foregroundStyle(
								.linearGradient(
									colors: [.green, .yellow, .orange, .red],
									startPoint: .bottom,
									endPoint: .top
								)
							)
							.alignsMarkStylesWithPlotArea()
						}
					}
					.chartXAxis(content: {
						AxisMarks(position: .top)
					})
					.chartXAxis(.automatic)
					.chartForegroundStyleScale([
						"Detection events": .green
					])
					.chartLegend(position: .automatic, alignment: .bottom)
				}
				.frame(minHeight: 250)
			}
			if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
				// Add a table for mac and ipad
				Table(detections) {
					TableColumn("Detection event") { d in
						Text(d.messagePayload ?? "Detected")
					}

					TableColumn("Timestamp") { d in
						Text(d.timestamp.formatted(date: .numeric, time: .shortened))
					}
					.width(min: 180)
				}
			} else {
				ScrollView {
					let columns = [
						GridItem(),
						GridItem()
					]
					LazyVGrid(columns: columns, alignment: .leading, spacing: 1) {
						GridRow {
							Text("Detection")
								.font(.caption)
								.fontWeight(.bold)
							Text("Timestamp")
								.font(.caption)
								.fontWeight(.bold)
						}
						ForEach(detections.filter( {$0.fromUser?.num ?? -1 == node.user?.num ?? 0})) { d in
							GridRow {
								Text(d.messagePayload ?? "Detected")
									.font(.caption)
								Text(d.timestamp.formatted(date: .numeric, time: .shortened))
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
			Button {
				exportString = detectionsToCsv(detections: chartData)
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
		.navigationTitle("Detection Sensor Log")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
		})
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("Detection Sensor Log".localized) \(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))_\(Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Detection Sensor metrics log download succeeded.")
				case .failure(let error):
					Logger.services.error("Detection Sensor log download failed: \(error.localizedDescription, privacy: .public).")
				}
			}
		)
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
	DetectionSensorLog(node: node)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
*/
