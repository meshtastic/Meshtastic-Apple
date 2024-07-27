//
//  DetectionSensorLog.swift
//  Meshtastic
//
//  Created by Ben on 8/22/23.
//

import SwiftUI
import Charts
import MeshtasticProtobufs
import OSLog

struct DetectionSensorLog: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@ObservedObject var node: NodeInfoEntity
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "messageTimestamp", ascending: false)],
				  predicate: NSPredicate(format: "portNum == %d", Int32(PortNum.detectionSensorApp.rawValue)), animation: .none)
	private var detections: FetchedResults<MessageEntity>

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
			let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
			let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
			if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
				// Add a table for mac and ipad
				Table(detections) {
					TableColumn("Detection event") { d in
						Text(d.messagePayload ?? "Detected")
					}

					TableColumn("timestamp") { d in
						Text(d.timestamp.formattedDate(format: dateFormatString))
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
							Text("timestamp")
								.font(.caption)
								.fontWeight(.bold)
						}
						ForEach(detections.filter({ detection in
							detection.fromUser?.num ?? -1 == node.user?.num ?? 0
						})) { detection in
							GridRow {
								Text(detection.messagePayload ?? "Detected")
									.font(.caption)
								Text(detection.timestamp.formattedDate(format: dateFormatString))
									.font(.caption)
							}
						}
					}
					.padding(.leading, 15)
					.padding(.trailing, 5)
				}
			}
		}
	}
}
