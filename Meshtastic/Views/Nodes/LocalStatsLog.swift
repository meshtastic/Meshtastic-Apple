//
//  LocalStatsLog.swift
//  Meshtastic
//
//  Copyright(c) Benjamin Faershtein 1/17/26.
//
import SwiftUI
import Charts
import OSLog

struct LocalStatsLog: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""

	@ObservedObject var node: NodeInfoEntity
	@State private var sortOrder = [KeyPathComparator(\TelemetryEntity.time, order: .reverse)]
	@State private var selection: TelemetryEntity.ID?
	@State private var chartSelection: Date?

	private var localStats: [TelemetryEntity] {
		let filtered = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 4"))
		return (filtered?.reversed() as? [TelemetryEntity]) ?? []
	}

	private var hasLocalStats: Bool {
		!localStats.isEmpty
	}

	private var chartData: [TelemetryEntity] {
		let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())
		return localStats.filter { $0.time != nil && $0.time! >= oneWeekAgo! }.sorted { $0.time! < $1.time! }
	}

	private var hasChartData: Bool {
		!chartData.isEmpty
	}

	private var dateFormatString: String {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMdjmma", options: 0, locale: Locale.current)
		return (localeDateFormat ?? "M/d/YY j:mma").replacingOccurrences(of: ",", with: "")
	}

	var body: some View {
		VStack {
			if hasLocalStats {
				if hasChartData {
					chartView
				}
				tableView
				buttonView
			} else {
				ContentUnavailableView("No Local Stats", systemImage: "waveform")
			}
		}
		.navigationTitle("Local Stats Log")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
		})
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("Local Stats Log".localized)"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Local stats log download succeeded.")
				case .failure(let error):
					Logger.services.error("Local stats log download failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		)
	}

	private var chartView: some View {
		GroupBox(label: Label("\(localStats.count) Readings Total", systemImage: "waveform")) {
			Chart(chartData) { point in
				if let pointTime = point.time, let noiseFloor = point.noiseFloor {
					LineMark(
						x: .value("Time", pointTime),
						y: .value("Noise Floor", noiseFloor)
					)
					.foregroundStyle(Color.accentColor)
					.interpolationMethod(.linear)
				}
				RuleMark(y: .value("Icky", -85))
					.lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
					.foregroundStyle(.red)
			}
			.chartXAxis(content: {
				AxisMarks(position: .top)
			})
			.chartXSelection(value: $chartSelection)
			.chartYScale(domain: -130 ... -60)
			.chartForegroundStyleScale([
				"Noise Floor": Color.accentColor
			])
			.chartLegend(position: .automatic, alignment: .bottom)
		}
		.frame(minHeight: 240)
	}

	@ViewBuilder
	private var tableView: some View {
		if idiom == .phone {
			phoneTableView
		} else {
			macTableView
		}
	}

	private var phoneTableView: some View {
		Table(localStats, selection: $selection, sortOrder: $sortOrder) {
			TableColumn("Local Stats") { ls in
				HStack {
					Text(ls.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized)
						.font(.caption)
						.fontWeight(.semibold)
					Spacer()
				}
				HStack {
					if let noiseFloor = ls.noiseFloor, noiseFloor != 0 {
						Text("Noise Floor \(noiseFloor.formatted(.number.precision(.fractionLength(1)))) dBm")
							.foregroundColor(noiseFloorColor(noiseFloor))
					} else {
						Text("Noise Floor No Reading")
							.foregroundColor(.gray)
					}
					Spacer()
				}
				HStack {
					Text("Relayed: \(ls.numTxRelay)")
					Text("Canceled: \(ls.numTxRelayCanceled)")
					Text("Dupes: \(ls.numRxDupe)")
					Spacer()
				}
				.font(.caption)
			}
			.width(ideal: 200, max: .infinity)
		}
	}

	private var macTableView: some View {
		Table(localStats, selection: $selection, sortOrder: $sortOrder) {
			TableColumn("Noise Floor") { ls in
				if let noiseFloor = ls.noiseFloor, noiseFloor != 0 {
					Text("\(noiseFloor.formatted(.number.precision(.fractionLength(1)))) dBm")
						.foregroundColor(noiseFloorColor(noiseFloor))
				} else {
					Text("No Reading")
						.foregroundColor(.gray)
				}
			}
			TableColumn("Uptime") { ls in
				if let uptimeSeconds = ls.uptimeSeconds {
					let now = Date.now
					let later = now + TimeInterval(uptimeSeconds)
					let components = (now..<later).formatted(.components(style: .narrow))
					Text(components)
				} else {
					Text(Constants.nilValueIndicator)
				}
			}
			.width(min: 100)
			TableColumn("Relayed") { ls in
				Text("\(ls.numTxRelay)")
			}
			.width(min: 80)
			TableColumn("Canceled") { ls in
				Text("\(ls.numTxRelayCanceled)")
			}
			.width(min: 80)
			TableColumn("Dupes") { ls in
				Text("\(ls.numRxDupe)")
			}
			.width(min: 80)
			TableColumn("Packets Tx") { ls in
				Text("\(ls.numPacketsTx)")
			}
			.width(min: 80)
			TableColumn("Packets Rx") { ls in
				Text("\(ls.numPacketsRx)")
			}
			.width(min: 80)
			TableColumn("Bad Rx") { ls in
				Text("\(ls.numPacketsRxBad)")
			}
			.width(min: 80)
			TableColumn("Nodes Online") { ls in
				Text("\(ls.numOnlineNodes)")
			}
			.width(min: 100)
			TableColumn("Timestamp") { ls in
				Text(ls.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized)
			}
			.width(min: 180)
		}
	}

	private var buttonView: some View {
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
				Button("Delete all local stats?", role: .destructive) {
					if clearTelemetry(destNum: node.num, metricsType: 4, context: context) {
						Logger.data.notice("Cleared Local Stats for \(node.num, privacy: .public)")
					} else {
						Logger.data.error("Clear Local Stats Log Failed")
					}
				}
			}

			Button {
				exportString = telemetryToCsvFile(telemetry: localStats, metricsType: 4)
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
			guard let metrics = localStats.first(where: { $0.id == newSelection }) else {
				return
			}
			chartSelection = metrics.time
		}
	}

	private func noiseFloorColor(_ value: Float) -> Color {
		if value < -100 {
			return .green
		} else if value < -95 {
			return .green
		} else if value < -90 {
			return .orange
		} else {
			return .red
		}
	}
}
