//
//  AirQualityMetricsLog.swift
//  Meshtastic
//
//  Particulate-matter (PM) air quality telemetry log (issue #2040).
//
import SwiftUI
import Charts
import OSLog
import SwiftData

struct AirQualityMetricsLog: View {

	@Environment(\.modelContext) private var context
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	/// Table on iPhone shows only its first column, even in a regular size class.
	private var showsWideTable: Bool {
		horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom != .phone
	}
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@Bindable var node: NodeInfoEntity

	@StateObject var columnList = MetricsColumnList.airQualityDefaultColumns
	@StateObject var seriesList = MetricsSeriesList.airQualityDefaultChartSeries

	@State var isEditingColumnConfiguration = false
	@State private var chartData: [TelemetryEntity] = []
	@State private var totalReadings = 0

	// AirQualityMetrics telemetry is stored with metricsType 3.
	private let metricsType: Int32 = 3

	var body: some View {
		VStack {
			// Gate on recent (last 7 days) data, not the all-time count: a node with only older
			// readings would otherwise satisfy the count but render an empty chart/table.
			if !chartData.isEmpty {
				VStack {
					if chartData.count > 0 {
						GroupBox(label: Label("\(totalReadings) Readings Total", systemImage: "chart.xyaxis.line")) {
							MetricsChartStack(groups: seriesList.chartGroups(forData: chartData), points: chartData)
						}
					}

					// Dynamic table column using SwiftUI Table requires TableColumnForEach which requires the target
					// to be bumped to 17.4 -- Until that happens, the existing non-configurable table is used.
					if showsWideTable {
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
					let wide = horizontalSizeClass == .regular
					let buttonSize: ControlSize = wide ? .large : .small
					let imageScale: Image.Scale = wide ? .medium : .small
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
					.hostedSheet(isPresented: self.$isEditingColumnConfiguration) {
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
					.hostedConfirmation(
						"Are you sure?",
						isPresented: $isPresentingClearLogConfirm,
						titleVisibility: .visible
						) {
							Button("Delete all air quality metrics?", role: .destructive) {
								Task {
									if await MeshPackets.shared.clearTelemetry(destNum: node.num, metricsType: metricsType) {
										Logger.services.info("Cleared Air Quality Metrics for \(node.num, privacy: .public)")
										await MainActor.run {
											refreshMetrics()
											NotificationCenter.default.post(name: .nodeLogAvailabilityDidChange, object: node.num)
										}
									} else {
										Logger.services.error("Clear Air Quality Metrics Log Failed")
									}
								}
							}
					}
					Button {
						exportString = telemetryToCsvFile(telemetry: chartData, metricsType: Int(metricsType))
						isExporting = true
					} label: {
						Label("Save", systemImage: "square.and.arrow.down")
							.imageScale(imageScale)
					}
					.hostedWindowOnly()
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(buttonSize)
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
			defaultFilename: CsvDocument.exportFilename("\(node.user?.longName ?? "Node") Air Quality Metrics Log \(Date.now.exportTimestamp)"),
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
		totalReadings = node.telemetryCount(ofType: metricsType, context: context)
		let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
		chartData = node.safeTelemetries(ofType: metricsType)
			.filter { ($0.time ?? Date.distantPast) >= oneWeekAgo }
			.sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
	}
}
