//
//  PowerMetricsLog.swift
//  Meshtastic
//
//  Created by Matthew Davies on 1/24/25.
//

import Foundation
import SwiftUI
import Charts
import OSLog

struct PowerMetricsLog: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Bindable var node: NodeInfoEntity
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	/// Table on iPhone shows only its first column, even in a regular size class.
	private var showsWideTable: Bool {
		horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom != .phone
	}
	@State private var sortOrder = [KeyPathComparator(\TelemetryEntity.time, order: .reverse)]
	@State private var selection: TelemetryEntity.ID?
	@State private var chartSelection: Date?

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""

	@State private var channelSelection = 0
	@State private var powerMetrics: [TelemetryEntity] = []
	@State private var chartData: [TelemetryEntity] = []
	@State private var totalReadings = 0

	// User-editable per-channel labels (e.g. "Solar", "Battery", "Load"), persisted per node so a
	// user can tell which line is which without memorizing their wiring. Empty entries fall back to
	// the generic "Channel N". Per meshtastic/design#53 / Meshtastic-Apple#2046.
	@State private var channelLabels: [String] = Array(repeating: "", count: TelemetryEntity.powerChannelCount)
	@State private var isEditingLabels = false
	/// The channels, counting from zero, that report anything. Only these are charted and listed.
	@State private var reportedChannels: [Int] = []

	var body: some View {
		VStack {
			if totalReadings > 0 {
				if chartData.count > 0 {
					GroupBox(label: Label("\(totalReadings) Readings Total", systemImage: "chart.xyaxis.line")) {

						// allow switching between the channels that report
						Picker("Select Channel", selection: $channelSelection) {
							ForEach(reportedChannels, id: \.self) { index in
								Text(displayLabel(index)).tag(index)
							}
						}

						// Volts and milliamps each get a chart of their own (design#53 requirement 5).
						VStack(spacing: 12) {
							if chartData.contains(where: { $0.powerVoltage(channel: channelSelection) != nil }) {
								powerChart(.voltage)
							}
							if chartData.contains(where: { $0.powerCurrent(channel: channelSelection) != nil }) {
								powerChart(.current)
							}
						}
					}
				}
				if !showsWideTable {
					Table(powerMetrics, selection: $selection, sortOrder: $sortOrder) {
						TableColumn("Timestamp") { m in
							HStack {
								Text(m.time?.formatted(date: .numeric, time: .shortened) ?? "Unknown Age".localized)
								ForEach(reportedChannels, id: \.self) { index in
									Spacer()
									VStack {
										Text(displayLabel(index))
										HStack {
											Image(systemName: "powerplug.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											Text(voltageText(m.powerVoltage(channel: index)))
										}
										HStack {
											Image(systemName: "bolt.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											Text(currentText(m.powerCurrent(channel: index)))
										}
									}
									.accessibilityElement(children: .combine)
								}
							}
						}
					}
					.onChange(of: selection) { _, newSelection in
						guard let metrics = powerMetrics.first(where: { $0.id == newSelection }) else {
							return
						}
						chartSelection = metrics.time
					}
				} else {
					Table(powerMetrics, selection: $selection, sortOrder: $sortOrder) {
						TableColumnForEach(tableColumns) { column in
							TableColumn(column.title) { dm in
								Text(column.isVoltage
									 ? voltageText(dm.powerVoltage(channel: column.channel))
									 : currentText(dm.powerCurrent(channel: column.channel)))
							}
							.width(min: 75)
						}
						TableColumn("Timestamp") { dm in
							Text(dm.time?.formatted(date: .numeric, time: .shortened) ?? "Unknown Age".localized)
						}
						.width(min: 180)

					}
					.onChange(of: selection) { _, newSelection in
						guard let metrics = powerMetrics.first(where: { $0.id == newSelection }) else {
							return
						}
						chartSelection = metrics.time
					}
				}
				HStack {
					Button(role: .destructive) {
						isPresentingClearLogConfirm = true
					} label: {
						Label("Clear Log", systemImage: "trash.fill")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(horizontalSizeClass == .regular ? .large : .regular)
					.padding(.bottom)
					.padding(.leading)
					.hostedConfirmation(
						"Are you sure?",
						isPresented: $isPresentingClearLogConfirm,
						titleVisibility: .visible
					) {
							Button("Delete Power metrics?", role: .destructive) {
								Task {
									if await MeshPackets.shared.clearTelemetry(destNum: node.num, metricsType: 2) {
										Logger.data.notice("Cleared Power Metrics for \(node.num, privacy: .public)")
										await MainActor.run {
											refreshMetrics()
											NotificationCenter.default.post(name: .nodeLogAvailabilityDidChange, object: node.num)
										}
									} else {
										Logger.data.error("Clear Power Metrics Log Failed")
									}
							}
						}
					}

					Button {
						exportString = telemetryToCsvFile(telemetry: powerMetrics, metricsType: 2)
						isExporting = true
					} label: {
						Label("Save", systemImage: "square.and.arrow.down")
					}
					.hostedWindowOnly()
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(horizontalSizeClass == .regular ? .large : .regular)
					.padding(.bottom)
					.padding(.trailing)
				}
				.onChange(of: selection) { _, newSelection in
					guard let metrics = powerMetrics.first(where: { $0.id == newSelection }) else {
						return
					}
					chartSelection = metrics.time
				}
			} else {
				ContentUnavailableView("No Power Metrics", systemImage: "slash.circle")
			}
		}
		.onAppear {
			refreshMetrics()
			channelLabels = loadChannelLabels()
		}
		.onChange(of: node.lastHeard) {
			refreshMetrics()
		}
		.navigationTitle("Power Metrics Log")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarLeading) {
				Button {
					isEditingLabels = true
				} label: {
					Label("Label Channels", systemImage: "pencil")
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.hostedSheet(isPresented: $isEditingLabels) {
			SheetNavigationStack {
				Form {
					Section {
						ForEach(0..<TelemetryEntity.powerChannelCount, id: \.self) { index in
							TextField("Channel \(index + 1)", text: $channelLabels[index])
								.autocorrectionDisabled()
						}
					} header: {
						Text("Power Channel Labels")
					} footer: {
						Text("Give each channel a name (e.g. Solar, Battery, Load). Leave blank to use the default \"Channel N\".")
					}
				}
				.navigationTitle("Label Power Channels")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button {
							channelLabels = loadChannelLabels()
							isEditingLabels = false
						} label: {
							Image(systemName: "xmark")
						}
						.accessibilityLabel(String(localized: "Cancel", comment: "VoiceOver: dismiss the label power channels sheet"))
					}
					ToolbarItem(placement: .confirmationAction) {
						Button("Save") {
							saveChannelLabels()
							isEditingLabels = false
						}
					}
				}
			}
			.trackScreen(.powerChannelLabels)
		}
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: CsvDocument.exportFilename("\(node.user?.longName ?? "Node") \("Power Metrics Log".localized) \(Date.now.exportTimestamp)"),
			onCompletion: { result in
				switch result {
				case .success:
					self.isExporting = false
					Logger.services.info("Power metrics log download succeeded.")
				case .failure(let error):
					Logger.services.error("Power metrics log download failed: \(error.localizedDescription, privacy: .public)")
				}
			}
			)
	}

	private func refreshMetrics() {
		totalReadings = node.telemetryCount(ofType: 2, context: context)
		powerMetrics = node.safeTelemetries(ofType: 2)
		let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
		chartData = powerMetrics
			.filter { ($0.time ?? Date.distantPast) >= oneWeekAgo }
			.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
		reportedChannels = powerMetrics.reportedPowerChannels
		// Open on a channel that has readings, not Channel 1 when it has none.
		let charted = chartData.reportedPowerChannels
		if !charted.contains(channelSelection), let first = charted.first {
			channelSelection = first
		}
	}

	// MARK: - Chart and table

	private struct PowerColumn: Identifiable {
		let channel: Int
		let isVoltage: Bool
		let title: String
		var id: String { "\(channel)-\(isVoltage)" }
	}

	private var tableColumns: [PowerColumn] {
		reportedChannels.flatMap { index in
			let name = displayLabel(index)
			return [
				PowerColumn(channel: index, isVoltage: true, title: String(localized: "\(name) Voltage", comment: "Power log column. %@ is the channel's label, such as Solar or Channel 1.")),
				PowerColumn(channel: index, isVoltage: false, title: String(localized: "\(name) Current", comment: "Power log column. %@ is the channel's label, such as Solar or Channel 1."))
			]
		}
	}

	private func voltageText(_ voltage: Float?) -> String {
		voltage.map { "\($0.formatted(.number.precision(.fractionLength(2))))V" } ?? Constants.nilValueIndicator
	}

	private func currentText(_ current: Float?) -> String {
		current.map { "\($0.formatted(.number.precision(.fractionLength(1))))mA" } ?? Constants.nilValueIndicator
	}

	private func powerChart(_ type: PowerMetricType) -> some View {
		let isVoltage = type == .voltage
		let name = isVoltage ? "Voltage".localized : "Current".localized
		let values = chartData.compactMap { isVoltage ? $0.powerVoltage(channel: channelSelection) : $0.powerCurrent(channel: channelSelection) }
		let range = MetricsAxis.padded(type.rawValue, minimumSpan: isVoltage ? 0.5 : 10).range(for: values)
		return Chart {
			ForEach(chartData, id: \.self) { point in
				if let value = isVoltage ? point.powerVoltage(channel: channelSelection) : point.powerCurrent(channel: channelSelection) {
					LineMark(
						x: .value("Time", point.time ?? Date()),
						y: .value(name, value)
					)
					.foregroundStyle(by: .value("Series", name))
					.interpolationMethod(.linear)
					.accessibilityLabel(isVoltage
						? String(localized: "Voltage at \((point.time ?? Date()).formatted(date: .abbreviated, time: .shortened))", comment: "VoiceOver label for a voltage point on the power metrics chart. %@ is the timestamp.")
						: String(localized: "Current at \((point.time ?? Date()).formatted(date: .abbreviated, time: .shortened))", comment: "VoiceOver label for a current point on the power metrics chart. %@ is the timestamp."))
					.accessibilityValue(isVoltage
						? String(localized: "\(value.formatted()) volts", comment: "VoiceOver value spoken as a voltage reading. %@ is the number.")
						: String(localized: "\(value.formatted()) milliamps", comment: "VoiceOver value spoken as a current reading in milliamps. %@ is the number."))
				}
			}

			if let chartSelection {
				RuleMark(x: .value("Second", chartSelection, unit: .second))
					.foregroundStyle(.tertiary.opacity(0.5))
					.accessibilityHidden(true)
			}
		}
		.chartXAxis(content: {
			AxisMarks(position: .top)
		})
		.chartXSelection(value: $chartSelection)
		.chartYScale(domain: range)
		.chartForegroundStyleScale([name: isVoltage ? Color.blue : Color.green])
		.chartLegend(position: .automatic, alignment: .bottom)
		.frame(height: 150)
	}

	// MARK: - Channel labels

	/// Persisted on `node.powerChannelLabels` (SwiftData) rather than `UserDefaults` so labels are
	/// deleted along with the node instead of accumulating indefinitely after it's forgotten.
	private func loadChannelLabels() -> [String] {
		let stored = node.powerChannelLabels
		return (0..<TelemetryEntity.powerChannelCount).map { index in index < stored.count ? stored[index] : "" }
	}

	private func saveChannelLabels() {
		node.powerChannelLabels = channelLabels
		do {
			try context.save()
		} catch let error as NSError {
			Logger.data.error("\(error.localizedDescription, privacy: .public)")
		}
	}

	/// The label shown for a power channel: the user's custom label, or the generic "Channel N" fallback.
	private func displayLabel(_ index: Int) -> String {
		PowerChannelLabel.name(index, in: channelLabels)
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
	PowerMetricsLog(node: node)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
*/
