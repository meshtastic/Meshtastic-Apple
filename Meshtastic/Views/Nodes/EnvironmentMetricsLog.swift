//
//  DeviceMetricsLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/7/22.
//
import SwiftUI
import Charts
import OSLog
import CoreData

struct EnvironmentMetricsLog: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@ObservedObject var node: NodeInfoEntity

	@StateObject var columnList = MetricsColumnList.environmentDefaultColumns
	@StateObject var seriesList = MetricsSeriesList.environmentDefaultChartSeries

	@State var isEditingColumnConfiguration = false
	
	@FetchRequest private var chartData: FetchedResults<TelemetryEntity>
	
	init(node: NodeInfoEntity) {
		self.node = node
		
		// Build fetch request:
		let request: NSFetchRequest<TelemetryEntity> = TelemetryEntity.fetchRequest()
		let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
		request.predicate = NSPredicate(format: "nodeTelemetry == %@ AND metricsType == 1 AND time >= %@", node, oneWeekAgo as NSDate)
		request.sortDescriptors = [NSSortDescriptor(key: "time", ascending: false)]
		_chartData = FetchRequest(fetchRequest: request)
	}
	
	var body: some View {
		VStack {
			if node.hasEnvironmentMetrics {
				let chartRange = applyMargins(seriesList.chartRange(forData: chartData))
				VStack {
					if chartData.count > 0 {
						GroupBox(label: Label("\(chartData.count) Readings Total", systemImage: "chart.xyaxis.line")) {
							Chart(seriesList.visible) { series in
								ForEach(chartData, id: \.time) { dataPoint in
									series.body(dataPoint, inChartRange: chartRange)
								}
							}
							.chartXAxis(content: {
								AxisMarks(position: .top)
							})
							.chartYScale(domain: chartRange)
							.chartForegroundStyleScale { (seriesName: String) -> AnyShapeStyle in
								return seriesList.foregroundStyle(forAbbreviatedName: seriesName, chartRange: chartRange) ?? AnyShapeStyle(Color.clear)
							}
							.chartLegend(position: .automatic, alignment: .bottom)
						}
					}

					// Dynamic table column using SwiftUI Table requires TableColumnForEach which requires the target
					// to be bumped to 17.4 -- Until that happens, the existing non-configurable table is used.
					if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
						// Add a table for mac and ipad
						Table(chartData) {
							TableColumnForEach(columnList.visible) { col in
								TableColumn(col.name) { em in
									col.body(em)
								}
							}
						}
					} else {
						ScrollView {
							LazyVGrid(columns: columnList.gridItems, alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
								GridRow {
									ForEach(columnList.visible) { col in
										Text(col.abbreviatedName)
											.font(.caption)
											.fontWeight(.bold)
									}
								}
								ForEach(chartData) { em  in
									GridRow {
										ForEach(columnList.visible) { col in
											col.body(em)
												.font(.caption)
										}
									}
								}
							}
							.padding(.leading, 15)
							.padding(.trailing, 5)
						}
					}
				}
				HStack {
					let isPadOrCatalyst = UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac
					let buttonSize: ControlSize =  isPadOrCatalyst ? .large : .small
					let imageScale: Image.Scale = isPadOrCatalyst ? .medium : .small
					Button {
						self.isEditingColumnConfiguration = true
					} label: {
						Label("Config", systemImage: "tablecells")
							.imageScale(imageScale)
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(buttonSize)
					.padding(.bottom)
					.padding(.leading)
					.sheet(isPresented: self.$isEditingColumnConfiguration) {
						MetricsColumnDetail(columnList: columnList, seriesList: seriesList)
					}
					Button(role: .destructive) {
						isPresentingClearLogConfirm = true
					} label: {
						Label("Clear", systemImage: "trash.fill")
							.imageScale(imageScale)
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(buttonSize)
					.padding(.bottom)
					.confirmationDialog(
						"Are you sure?",
						isPresented: $isPresentingClearLogConfirm,
						titleVisibility: .visible
					) {
						Button("Delete all environment metrics?", role: .destructive) {
							Task {
								if await MeshPackets.shared.clearTelemetry(destNum: node.num, metricsType: 1) {
									Logger.services.error("Clear Environment Metrics Log Failed")
								}
							}
						}
					}
					Button {
						exportString = telemetryToCsvFile(telemetry: chartData, metricsType: 1)
						isExporting = true
					} label: {
						Label("Save", systemImage: "square.and.arrow.down")
							.imageScale(imageScale)
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(buttonSize)
					.padding(.bottom)
					.padding(.trailing)
				}

			} else {
				ContentUnavailableView("No Environment Metrics", systemImage: "slash.circle")
			}
		}

		.navigationTitle("Environment Metrics Log")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
		})
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") Environment Metrics Log"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Environment metrics log download succeeded.")
				case .failure(let error):
					Logger.services.error("Environment metrics log download failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		)
	}

	// Helper.  Adds a little buffer to the Y axis range, but keeps Y=0
	func applyMargins<T>(_ range: ClosedRange<T>) -> ClosedRange<T> where T: BinaryFloatingPoint {
		let span = range.upperBound - range.lowerBound
		let margin = span * 0.1
		let lower = range.lowerBound == 0.0 ? 0.0  : range.lowerBound - margin
		let upper = range.upperBound + margin
		return lower...upper
	}
}
