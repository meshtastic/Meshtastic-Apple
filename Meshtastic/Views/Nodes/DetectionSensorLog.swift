//
//  DetectionSensorLog.swift
//  Meshtastic
//
//  Created by Ben on 8/22/23.
//

import SwiftUI
@preconcurrency import SwiftData
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
	@State private var detections: [MessageEntity] = []
	@State private var chartData: [MessageEntity] = []

	init(node: NodeInfoEntity) {
		self.node = node
	}

	var body: some View {
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
							.accessibilityLabel(String(localized: "Detection event at \(point.timestamp.formatted(date: .abbreviated, time: .shortened))", comment: "VoiceOver label for a detection-event bar on the detection sensor chart. %@ is the timestamp."))
							.accessibilityValue(String(localized: "Detected", comment: "VoiceOver value spoken for a detection-event bar on the detection sensor chart."))
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
						"Detection events".localized: .green
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
						ForEach(detections) { d in
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
		.onAppear {
			refreshDetections()
		}
		.onChange(of: node.lastHeard) {
			refreshDetections()
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
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("Detection Sensor Log".localized) \(Date.now.exportTimestamp)"),
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

	private func refreshDetections() {
		guard let nodeNum = node.user?.num else {
			detections = []
			chartData = []
			return
		}
		let portNum: Int32 = 10
		let sevenDaysAgoTimestamp = Int32((Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast).timeIntervalSince1970)
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.portNum == portNum && $0.messageTimestamp >= sevenDaysAgoTimestamp && $0.fromUser?.num == nodeNum
			},
			sortBy: [SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse)]
		)
		descriptor.fetchLimit = 500
		detections = (try? context.fetch(descriptor)) ?? []
		let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date.distantPast
		chartData = detections
			.filter { $0.timestamp >= oneDayAgo }
			.sorted { $0.timestamp < $1.timestamp }
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
