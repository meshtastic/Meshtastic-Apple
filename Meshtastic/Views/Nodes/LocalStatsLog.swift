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

	@EnvironmentObject var accessoryManager: AccessoryManager
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@State private var isPresentingNoiseFloorInfo = false

	@Bindable var node: NodeInfoEntity
	@State private var sortOrder = [KeyPathComparator(\TelemetryEntity.time, order: .reverse)]
	@State private var selection: TelemetryEntity.ID?
	@State private var chartSelection: Date?
	@State private var selectedChartRange: LocalStatsChartRange = .day
	@State private var chartScrollPosition = Date()

	private var localStats: [TelemetryEntity] {
		node.safeTelemetries(ofType: 4)
	}

	private var chartData: [TelemetryEntity] {
		return localStats
			.filter { $0.time != nil }
			.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
	}

	private var noiseFloorReadings: [LocalStatsChartPoint] {
		chartData.compactMap { point in
			guard let time = point.time, let noiseFloor = point.noiseFloor else { return nil }
			return LocalStatsChartPoint(time: time, noiseFloor: noiseFloor)
		}
	}

	private var selectedChartPoint: LocalStatsChartPoint? {
		guard let chartSelection else { return nil }
		return noiseFloorReadings.min { lhs, rhs in
			abs(lhs.time.timeIntervalSince(chartSelection)) < abs(rhs.time.timeIntervalSince(chartSelection))
		}
	}

	private var latestNoiseFloorReading: LocalStatsChartPoint? {
		noiseFloorReadings.last
	}

	private var chartDataDuration: TimeInterval {
		guard let firstTime = noiseFloorReadings.first?.time,
			  let lastTime = noiseFloorReadings.last?.time else {
			return LocalStatsChartRange.minimumVisibleDuration
		}
		return max(lastTime.timeIntervalSince(firstTime), LocalStatsChartRange.minimumVisibleDuration)
	}

	private var chartVisibleDuration: TimeInterval {
		chartVisibleDuration(for: selectedChartRange)
	}

	private var chartYDomain: ClosedRange<Int> {
		let values = noiseFloorReadings.map { Int($0.noiseFloor) }
		guard let minValue = values.min(), let maxValue = values.max() else {
			return -130 ... -60
		}
		let lower = min(minValue - 5, -115)
		let upper = max(maxValue + 5, -75)
		return lower ... upper
	}

	private var averageNoiseFloor: Int? {
		let values = noiseFloorReadings.map { Int($0.noiseFloor) }
		guard !values.isEmpty else { return nil }
		return values.reduce(0, +) / values.count
	}

	private var dateFormatString: String {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMdjmma", options: 0, locale: Locale.current)
		return (localeDateFormat ?? "M/d/YY j:mma").replacingOccurrences(of: ",", with: "")
	}

	var body: some View {
		VStack {
			if node.hasLocalStats {
				if !noiseFloorReadings.isEmpty {
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
			resetChartViewToLatest()
		}
	}

	private var chartView: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 10) {
				chartSummaryView
				chartControlsView
				Chart {
					ForEach(noiseFloorReadings) { point in
						AreaMark(
							x: .value("Time", point.time),
							yStart: .value("Floor", chartYDomain.lowerBound),
							yEnd: .value("Noise Floor", Int(point.noiseFloor))
						)
						.foregroundStyle(
							LinearGradient(
								colors: [.accentColor.opacity(0.24), .accentColor.opacity(0.02)],
								startPoint: .top,
								endPoint: .bottom
							)
						)

						LineMark(
							x: .value("Time", point.time),
							y: .value("Noise Floor", Int(point.noiseFloor))
						)
						.foregroundStyle(Color.accentColor)
						.lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
						.interpolationMethod(.catmullRom)
					}
					RuleMark(y: .value("Busy Floor (-85 dBm)", -85))
						.lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
						.foregroundStyle(.red)
						.annotation(position: .topTrailing, alignment: .trailing) {
							Text("busy")
								.font(.caption2)
								.foregroundStyle(.secondary)
						}
					if let selectedChartPoint {
						RuleMark(x: .value("Selected", selectedChartPoint.time))
							.foregroundStyle(.secondary.opacity(0.45))
						PointMark(
							x: .value("Time", selectedChartPoint.time),
							y: .value("Noise Floor", Int(selectedChartPoint.noiseFloor))
						)
						.foregroundStyle(noiseFloorColor(selectedChartPoint.noiseFloor))
						.symbolSize(56)
						.annotation(position: .top, alignment: .center) {
							VStack(alignment: .leading, spacing: 2) {
								Text("\(selectedChartPoint.noiseFloor) dBm")
									.font(.caption.bold())
								Text(selectedChartPoint.time.formatted(date: .omitted, time: .shortened))
									.font(.caption2)
									.foregroundStyle(.secondary)
							}
							.padding(.horizontal, 8)
							.padding(.vertical, 6)
							.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
						}
					}
				}
				.chartXAxis {
					AxisMarks(position: .bottom, values: .automatic(desiredCount: idiom == .phone ? 3 : 6))
				}
				.chartYAxis {
					AxisMarks(position: .leading)
				}
				.chartXSelection(value: $chartSelection)
				.chartYScale(domain: chartYDomain)
				.chartScrollableAxes(.horizontal)
				.chartXVisibleDomain(length: chartVisibleDuration)
				.chartScrollPosition(x: $chartScrollPosition)
				.chartLegend(.hidden)
				.frame(height: idiom == .phone ? 210 : 300)
			}
		} label: {
			Label("\(localStats.count) Local Stats Readings", systemImage: "chart.xyaxis.line")
		}
		.padding(.horizontal)
		.onChange(of: selectedChartRange) { _, newRange in
			resetChartViewToLatest(for: newRange)
		}
	}

	@ViewBuilder
	private var chartSummaryView: some View {
		HStack(spacing: 8) {
			LocalStatsMetricPill(
				title: "Latest",
				value: latestNoiseFloorReading.map { "\($0.noiseFloor) dBm" } ?? Constants.nilValueIndicator,
				color: latestNoiseFloorReading.map { noiseFloorColor($0.noiseFloor) } ?? .secondary
			)
			LocalStatsMetricPill(
				title: "Average",
				value: averageNoiseFloor.map { "\($0) dBm" } ?? Constants.nilValueIndicator,
				color: .secondary
			)
			LocalStatsMetricPill(
				title: "Samples",
				value: "\(noiseFloorReadings.count)",
				color: .secondary
			)
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
					Text(ls.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized)
						.font(.caption)
						.fontWeight(.semibold)
					Spacer()
				}
				HStack {
					if let noiseFloor = ls.noiseFloor {
						Text("Noise Floor \(noiseFloor) dBm")
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
				if let noiseFloor = ls.noiseFloor {
					Text("\(noiseFloor) dBm")
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
					Task {
						if await MeshPackets.shared.clearTelemetry(destNum: node.num, metricsType: 4) {
							Logger.data.notice("Cleared Local Stats for \(node.num, privacy: .public)")
						} else {
							Logger.data.error("Clear Local Stats Log Failed")
						}
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

private struct LocalStatsMetricPill: View {
	let title: LocalizedStringKey
	let value: String
	let color: Color

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(title)
				.font(.caption2)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.callout.weight(.semibold))
				.foregroundStyle(color)
				.monospacedDigit()
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
