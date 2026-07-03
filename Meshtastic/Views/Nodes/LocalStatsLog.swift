//
//  LocalStatsLog.swift
//  Meshtastic
//
//  Copyright(c) Benjamin Faershtein 1/17/26.
//

import SwiftUI
import UIKit
import Charts
import OSLog

struct LocalStatsLog: View {

	@EnvironmentObject var accessoryManager: AccessoryManager
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@State private var isPresentingNoiseFloorInfo = false

	@Bindable var node: NodeInfoEntity
	@State private var sortOrder = [KeyPathComparator(\TelemetryEntity.time, order: .reverse)]
	@State private var selection: TelemetryEntity.ID?
	@State private var selectedChartRange: LocalStatsChartRange = .day
	@State private var chartScrollPosition = Date()

	// Derived data is cached in @State and recomputed only when the underlying telemetry
	// changes (refreshData), NOT in `body`. `localStats` is a SwiftData fetch
	// (node.safeTelemetries), and the chart binds its scroll offset to @State
	// (chartScrollPosition), so `body` re-evaluates on every scroll frame. Recomputing
	// these getters there fired ~8 fetches + sorts per frame and janked scrolling.
	@State private var localStats: [TelemetryEntity] = []
	@State private var noiseFloorReadings: [LocalStatsChartPoint] = []
	@State private var chartYDomain: ClosedRange<Int> = -130 ... -60
	@State private var chartDataDuration: TimeInterval = LocalStatsChartRange.minimumVisibleDuration
	@State private var didLoad = false

	private var chartVisibleDuration: TimeInterval {
		chartVisibleDuration(for: selectedChartRange)
	}

	private var chartXAxisLabelCount: Int {
		idiom == .phone ? 2 : 6
	}

	private var chartXAxisFormat: Date.FormatStyle {
		let dayDuration = LocalStatsChartRange.day.duration ?? 24 * 60 * 60
		if chartVisibleDuration <= dayDuration {
			return Date.FormatStyle()
				.hour(.twoDigits(amPM: .omitted))
				.minute()
		}
		return Date.FormatStyle()
			.month(.defaultDigits)
			.day(.defaultDigits)
	}

	private var dateFormatString: String {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMdjmma", options: 0, locale: Locale.current)
		return (localeDateFormat ?? "M/d/YY j:mma").replacingOccurrences(of: ",", with: "")
	}

	var body: some View {
		VStack {
			if !localStats.isEmpty {
				if !noiseFloorReadings.isEmpty {
					chartView
				}
				tableView
			} else if didLoad {
				ContentUnavailableView("No Local Stats", systemImage: "waveform")
			}
			buttonView
		}
		.navigationTitle("Local Stats Log")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
			ToolbarItem(placement: .topBarLeading) {
				Button {
					isPresentingNoiseFloorInfo = true
				} label: {
					Label("Noise Floor Info", systemImage: "info.circle")
				}
			}
		}
		.sheet(isPresented: $isPresentingNoiseFloorInfo) {
			NavigationStack {
				NoiseFloorInfoView()
					.navigationTitle("Noise Floor")
					.navigationBarTitleDisplayMode(.inline)
					.toolbar {
						ToolbarItem(placement: .confirmationAction) {
							Button("Done") {
								isPresentingNoiseFloorInfo = false
							}
						}
					}
			}
			.presentationDetents([.medium])
		}
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("Local Stats Log".localized) \(Date.now.exportTimestamp)"),
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
		.onAppear {
			refreshData()
			resetChartViewToLatest()
		}
		.onChange(of: node.lastHeard) {
			// New packets (including local-stats telemetry) update lastHeard; refetch then.
			// Scrolling the chart does not touch lastHeard, so it never triggers a refetch.
			refreshData()
		}
	}

	private var chartView: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 10) {
				chartControlsView
				Chart {
					ForEach(noiseFloorReadings) { point in
						LineMark(
							x: .value("Time", point.time),
							y: .value("Noise Floor", Int(point.noiseFloor))
						)
						.foregroundStyle(Color.accentColor)
						.interpolationMethod(.linear)
					}
					if noiseFloorReadings.count == 1, let point = noiseFloorReadings.first {
						PointMark(
							x: .value("Time", point.time),
							y: .value("Noise Floor", Int(point.noiseFloor))
						)
						.foregroundStyle(Color.accentColor)
					}
					RuleMark(y: .value("Busy Floor (-85 dBm)", -85))
						.lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
						.foregroundStyle(.red)
				}
				.chartXAxis {
					AxisMarks(position: .bottom, values: .automatic(desiredCount: chartXAxisLabelCount)) { _ in
						AxisGridLine()
						AxisTick()
						AxisValueLabel(format: chartXAxisFormat)
					}
				}
				.chartYAxis {
					AxisMarks(position: .leading)
				}
				.chartYScale(domain: chartYDomain)
				.chartScrollableAxes(.horizontal)
				.chartXVisibleDomain(length: chartVisibleDuration)
				.chartScrollPosition(x: $chartScrollPosition)
				.chartLegend(.hidden)
				.frame(height: idiom == .phone ? 240 : 320)
				.padding(.bottom, 8)
			}
		} label: {
			Label("\(localStats.count) Local Stats Readings", systemImage: "chart.xyaxis.line")
		}
		.padding(.horizontal)
		.onChange(of: selectedChartRange) { _, newRange in
			resetChartViewToLatest(for: newRange)
		}
	}

	private var chartControlsView: some View {
		HStack(spacing: 8) {
			Picker("Visible Range", selection: $selectedChartRange) {
				ForEach(LocalStatsChartRange.allCases) { range in
					Text(range.title).tag(range)
				}
			}
			.pickerStyle(.segmented)

			Button {
				resetChartViewToLatest()
			} label: {
				Label("Latest", systemImage: "forward.end")
					.labelStyle(.iconOnly)
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.small)
			.accessibilityHint("Scrolls the chart to the newest reading")
		}
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
					CopyableLocalStatsField(
						timestampText(for: ls),
						title: "Timestamp",
						font: .caption,
						fontWeight: .semibold
					)
					Spacer()
				}
				HStack {
					CopyableLocalStatsField(
						phoneNoiseFloorText(for: ls),
						title: "Noise Floor",
						color: noiseFloorTextColor(for: ls)
					)
					Spacer()
				}
				HStack {
					CopyableLocalStatsField("Relayed: \(ls.numTxRelay)", title: "Relayed")
					CopyableLocalStatsField("Canceled: \(ls.numTxRelayCanceled)", title: "Canceled")
					CopyableLocalStatsField("Dupes: \(ls.numRxDupe)", title: "Dupes")
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
				CopyableLocalStatsField(
					noiseFloorValueText(for: ls),
					title: "Noise Floor",
					color: noiseFloorTextColor(for: ls)
				)
			}
			TableColumn("Uptime") { ls in
				CopyableLocalStatsField(uptimeText(for: ls), title: "Uptime")
			}
			.width(min: 100)
			TableColumn("Relayed") { ls in
				CopyableLocalStatsField("\(ls.numTxRelay)", title: "Relayed")
			}
			.width(min: 80)
			TableColumn("Canceled") { ls in
				CopyableLocalStatsField("\(ls.numTxRelayCanceled)", title: "Canceled")
			}
			.width(min: 80)
			TableColumn("Dupes") { ls in
				CopyableLocalStatsField("\(ls.numRxDupe)", title: "Dupes")
			}
			.width(min: 80)
			TableColumn("Packets Tx") { ls in
				CopyableLocalStatsField("\(ls.numPacketsTx)", title: "Packets Tx")
			}
			.width(min: 80)
			TableColumn("Packets Rx") { ls in
				CopyableLocalStatsField("\(ls.numPacketsRx)", title: "Packets Rx")
			}
			.width(min: 80)
			TableColumn("Bad Rx") { ls in
				CopyableLocalStatsField("\(ls.numPacketsRxBad)", title: "Bad Rx")
			}
			.width(min: 80)
			TableColumn("Nodes Online") { ls in
				CopyableLocalStatsField("\(ls.numOnlineNodes)", title: "Nodes Online")
			}
			.width(min: 100)
			TableColumn("Timestamp") { ls in
				CopyableLocalStatsField(timestampText(for: ls), title: "Timestamp")
			}
			.width(min: 180)
		}
	}

	private var buttonView: some View {
		HStack(spacing: 8) {
			if !localStats.isEmpty {
				Button(role: .destructive) {
					isPresentingClearLogConfirm = true
				} label: {
					Label {
						Text("Clear")
							.lineLimit(1)
					} icon: {
						Image(systemName: "trash.fill")
					}
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(idiom == .phone ? .regular : .large)
				.confirmationDialog(
					"Are you sure?",
					isPresented: $isPresentingClearLogConfirm,
					titleVisibility: .visible
				) {
					Button("Delete all local stats?", role: .destructive) {
						Task { @MainActor in
							if await MeshPackets.shared.clearTelemetry(destNum: node.num, metricsType: 4) {
								Logger.data.notice("Cleared Local Stats for \(node.num, privacy: .public)")
								refreshData()
							} else {
								Logger.data.error("Clear Local Stats Log Failed")
							}
						}
					}
				}
			}

			RequestLocalStatsButton(
				node: node,
				title: "Request",
				cooldownTitle: "Wait",
				systemImage: "arrow.clockwise"
			)
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(idiom == .phone ? .regular : .large)

			if !localStats.isEmpty {
				Button {
					exportString = telemetryToCsvFile(telemetry: localStats, metricsType: 4)
					isExporting = true
				} label: {
					Label {
						Text("Save")
							.lineLimit(1)
					} icon: {
						Image(systemName: "square.and.arrow.down")
					}
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(idiom == .phone ? .regular : .large)
			}
		}
		.frame(maxWidth: .infinity)
		.padding(.horizontal)
		.padding(.bottom)
		.onChange(of: selection) { _, newSelection in
			guard let metrics = localStats.first(where: { $0.id == newSelection }) else {
				return
			}
			if let time = metrics.time {
				chartScrollPosition = scrollStart(containing: time)
			}
		}
	}

	private func chartVisibleDuration(for range: LocalStatsChartRange) -> TimeInterval {
		guard let duration = range.duration else {
			return chartDataDuration
		}
		return min(duration, chartDataDuration)
	}

	private func resetChartViewToLatest(for range: LocalStatsChartRange? = nil) {
		guard let firstTime = noiseFloorReadings.first?.time,
			  let latestTime = noiseFloorReadings.last?.time else {
			return
		}
		let duration = chartVisibleDuration(for: range ?? selectedChartRange)
		chartScrollPosition = max(firstTime, latestTime.addingTimeInterval(-duration))
	}

	private func scrollStart(containing date: Date) -> Date {
		guard let firstTime = noiseFloorReadings.first?.time,
			  let latestTime = noiseFloorReadings.last?.time else {
			return date
		}
		let visibleDuration = chartVisibleDuration
		let lowerBound = firstTime
		let upperBound = max(firstTime, latestTime.addingTimeInterval(-visibleDuration))
		let centeredStart = date.addingTimeInterval(-visibleDuration / 2)
		return min(max(centeredStart, lowerBound), upperBound)
	}

	private func noiseFloorColor(_ value: Int32) -> Color {
		if value < -95 {
			return .green
		} else if value < -90 {
			return .orange
		} else {
			return .red
		}
	}

	private func timestampText(for localStats: TelemetryEntity) -> String {
		localStats.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized
	}

	private func phoneNoiseFloorText(for localStats: TelemetryEntity) -> String {
		guard let noiseFloor = localStats.noiseFloor else {
			return "Noise Floor No Reading"
		}
		return "Noise Floor \(noiseFloor) dBm"
	}

	private func noiseFloorValueText(for localStats: TelemetryEntity) -> String {
		guard let noiseFloor = localStats.noiseFloor else {
			return "No Reading"
		}
		return "\(noiseFloor) dBm"
	}

	private func noiseFloorTextColor(for localStats: TelemetryEntity) -> Color {
		guard let noiseFloor = localStats.noiseFloor else {
			return .gray
		}
		return noiseFloorColor(noiseFloor)
	}

	private func uptimeText(for localStats: TelemetryEntity) -> String {
		guard let uptimeSeconds = localStats.uptimeSeconds else {
			return Constants.nilValueIndicator
		}
		let now = Date.now
		let later = now + TimeInterval(uptimeSeconds)
		return (now..<later).formatted(.components(style: .narrow))
	}
}

private extension LocalStatsLog {
	/// Single source of the view's derived data. Runs one SwiftData fetch and recomputes
	/// the cached chart inputs. Called on appear, when the node hears new packets, and
	/// after a clear — never from `body`, so chart scrolling does no fetching or sorting.
	@MainActor
	func refreshData() {
		let stats = node.safeTelemetries(ofType: 4)
		localStats = stats

		// safeTelemetries already returns rows sorted by time descending; compactMap
		// preserves that order, so reversing yields ascending without a second sort.
		let readings = Array(
			stats.compactMap { point -> LocalStatsChartPoint? in
				guard let time = point.time, let noiseFloor = point.noiseFloor else { return nil }
				return LocalStatsChartPoint(time: time, noiseFloor: noiseFloor)
			}.reversed()
		)
		noiseFloorReadings = readings

		let values = readings.map { Int($0.noiseFloor) }
		if let minValue = values.min(), let maxValue = values.max() {
			chartYDomain = min(minValue - 5, -115) ... max(maxValue + 5, -75)
		} else {
			chartYDomain = -130 ... -60
		}

		if let firstTime = readings.first?.time, let lastTime = readings.last?.time {
			chartDataDuration = max(lastTime.timeIntervalSince(firstTime), LocalStatsChartRange.minimumVisibleDuration)
		} else {
			chartDataDuration = LocalStatsChartRange.minimumVisibleDuration
		}

		didLoad = true
	}
}

private struct CopyableLocalStatsField: View {
	let value: String
	let title: String
	let font: Font?
	let fontWeight: Font.Weight?
	let color: Color?

	init(
		_ value: String,
		title: String,
		font: Font? = nil,
		fontWeight: Font.Weight? = nil,
		color: Color? = nil
	) {
		self.value = value
		self.title = title
		self.font = font
		self.fontWeight = fontWeight
		self.color = color
	}

	var body: some View {
		Text(value)
			.font(font)
			.fontWeight(fontWeight)
			.foregroundColor(color)
			.textSelection(.enabled)
			.contextMenu {
				Button {
					UIPasteboard.general.string = value
				} label: {
					Label("Copy \(title)", systemImage: "doc.on.doc")
				}
			}
	}
}

private struct LocalStatsChartPoint: Identifiable {
	let time: Date
	let noiseFloor: Int32

	var id: Date { time }
}

private enum LocalStatsChartRange: String, CaseIterable, Identifiable {
	case hour
	case sixHours
	case day
	case week
	case all

	static let minimumVisibleDuration: TimeInterval = 15 * 60

	var id: String { rawValue }

	var title: String {
		switch self {
		case .hour:
			return "1h"
		case .sixHours:
			return "6h"
		case .day:
			return "24h"
		case .week:
			return "7d"
		case .all:
			return "All"
		}
	}

	var duration: TimeInterval? {
		switch self {
		case .hour:
			return 60 * 60
		case .sixHours:
			return 6 * 60 * 60
		case .day:
			return 24 * 60 * 60
		case .week:
			return 7 * 24 * 60 * 60
		case .all:
			return nil
		}
	}
}

private struct NoiseFloorInfoView: View {
	var body: some View {
		List {
			Section {
				Label("Lower values usually mean a quieter receiver environment.", systemImage: "speaker.wave.1")
				Label("Readings can vary quickly with nearby transmitters, antenna setup, filters, and local interference.", systemImage: "antenna.radiowaves.left.and.right")
				Label("The red reference line marks a busy -85 dBm floor, not a hard failure threshold.", systemImage: "exclamationmark.triangle")
			} header: {
				Text("How to read it")
			}
		}
	}
}
