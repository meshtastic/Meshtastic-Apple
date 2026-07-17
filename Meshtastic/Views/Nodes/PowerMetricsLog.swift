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
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
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
	@State private var channelLabels: [String] = ["", "", ""]
	@State private var isEditingLabels = false

	var minMax: (min: Double, max: Double) {
		let allValues = powerMetrics.flatMap { [
			$0.powerCh1Voltage,
			$0.powerCh1Current,
			$0.powerCh2Voltage,
			$0.powerCh2Current,
			$0.powerCh3Voltage,
			$0.powerCh3Current
			].compactMap({$0}) // Remove nils
		}

		guard !allValues.isEmpty else {
			return (min: -10, max: 10)
		}

		return (min: floor(Double(allValues.min()!)), max: ceil(Double(allValues.max()!)))
	}

	var body: some View {
		VStack {
			if totalReadings > 0 {
				if chartData.count > 0 {
					GroupBox(label: Label("\(totalReadings) Readings Total", systemImage: "chart.xyaxis.line")) {

						// allow switching between different channels
						Picker("Select Channel", selection: $channelSelection) {
							Text(displayLabel(0)).tag(0)
							Text(displayLabel(1)).tag(1)
							Text(displayLabel(2)).tag(2)
						}

						Chart {
							ForEach(chartData, id: \.self) { point in

								let voltage = channelSelection == 0 ? point.powerCh1Voltage : channelSelection == 1 ? point.powerCh2Voltage : point.powerCh3Voltage
								let current = channelSelection == 0 ? point.powerCh1Current : channelSelection == 1 ? point.powerCh2Current : point.powerCh3Current

								if let voltage {
									LineMark(
										x: .value("Time", point.time ?? Date()),
										y: .value("Voltage", voltage)
									)
									.foregroundStyle(by: .value("Series", "Voltage"))
									.interpolationMethod(.linear)
									.accessibilityLabel("Voltage")
									.accessibilityValue("X: \(point.time ?? Date()), Y: \(voltage)")
								}

								if let current {
									LineMark(
										x: .value("Time", point.time ?? Date()),
										y: .value("Current", current)
									)
									.foregroundStyle(by: .value("Series", "Current"))
									.interpolationMethod(.linear)
									.accessibilityLabel("Current")
									.accessibilityValue("X: \(point.time ?? Date()), Y: \(current)")
								}
							}

							if let chartSelection {
								RuleMark(x: .value("Second", chartSelection, unit: .second))
									.foregroundStyle(.tertiary.opacity(0.5))
							}

						}
						.chartXAxis(content: {
							AxisMarks(position: .top)
						})
						.chartXAxis(.automatic)
						.chartXSelection(value: $chartSelection)
						.chartYScale(domain: minMax.min...minMax.max)
						.chartForegroundStyleScale([
							"Voltage": .blue,
							"Current": .green
						])
						.chartLegend(position: .automatic, alignment: .bottom)
					}
				}
				if idiom == .phone {
					Table(powerMetrics, selection: $selection, sortOrder: $sortOrder) {
						TableColumn("Timestamp") { m in
							HStack {
								Text(m.time?.formatted(date: .numeric, time: .shortened) ?? "Unknown Age".localized)
								Spacer()
								HStack {
									VStack {
										Text(displayLabel(0))
										HStack {
											Image(systemName: "powerplug.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											m.powerCh1Voltage.map { Text("\(String(format: "%.2f", $0))V") } ?? Text(Constants.nilValueIndicator)
										}
										HStack {
											Image(systemName: "bolt.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											m.powerCh1Current.map { Text("\(String(format: "%.2f", $0))mA") } ?? Text(Constants.nilValueIndicator)
										}
									}
								}
								Spacer()
								HStack {
									VStack {
										Text(displayLabel(1))
										HStack {
											Image(systemName: "powerplug.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											m.powerCh2Voltage.map { Text("\(String(format: "%.2f", $0))V") } ?? Text(Constants.nilValueIndicator)
										}
										HStack {
											Image(systemName: "bolt.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											m.powerCh2Current.map { Text("\(String(format: "%.2f", $0))mA") } ?? Text(Constants.nilValueIndicator)
										}
									}
								}
								Spacer()
								HStack {
									VStack {
										Text(displayLabel(2))
										HStack {
											Image(systemName: "powerplug.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											m.powerCh3Voltage.map { Text("\(String(format: "%.2f", $0))V") } ?? Text(Constants.nilValueIndicator)
										}
										HStack {
											Image(systemName: "bolt.fill")
												.font(.caption)
												.symbolRenderingMode(.multicolor)
											m.powerCh3Current.map { Text("\(String(format: "%.2f", $0))mA") } ?? Text(Constants.nilValueIndicator)
										}
									}
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
						TableColumn("Ch1 Voltage") { dm in
							dm.powerCh1Voltage.map { Text("\(String(format: "%.2f", $0))V") } ?? Text(Constants.nilValueIndicator)
						}
						.width(min: 75)
						TableColumn("Ch1 Current") { dm in
							dm.powerCh1Current.map { Text("\(String(format: "%.2f", $0))mA") } ?? Text(Constants.nilValueIndicator)
						}
						.width(min: 75)
						TableColumn("Ch2 Voltage") { dm in
							dm.powerCh2Voltage.map { Text("\(String(format: "%.2f", $0))V") } ?? Text(Constants.nilValueIndicator)
						}
						.width(min: 75)
						TableColumn("Ch2 Current") { dm in
							dm.powerCh2Current.map { Text("\(String(format: "%.2f", $0))mA") } ?? Text(Constants.nilValueIndicator)
						}
						.width(min: 75)
						TableColumn("Ch3 Voltage") { dm in
							dm.powerCh3Voltage.map { Text("\(String(format: "%.2f", $0))V") } ?? Text(Constants.nilValueIndicator)
						}
						.width(min: 75)
						TableColumn("Ch3 Current") { dm in
							dm.powerCh3Current.map { Text("\(String(format: "%.2f", $0))mA") } ?? Text(Constants.nilValueIndicator)
						}
						.width(min: 75)
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
					.controlSize(idiom == .phone ? .regular : .large)
					.padding(.bottom)
					.padding(.leading)
					.confirmationDialog(
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
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(idiom == .phone ? .regular : .large)
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
		.sheet(isPresented: $isEditingLabels) {
			NavigationStack {
				Form {
					Section {
						ForEach(0..<3, id: \.self) { index in
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
						Button("Cancel") {
							channelLabels = loadChannelLabels()
							isEditingLabels = false
						}
					}
					ToolbarItem(placement: .confirmationAction) {
						Button("Save") {
							saveChannelLabels()
							isEditingLabels = false
						}
					}
				}
			}
		}
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") \("Power Metrics Log".localized) \(Date.now.exportTimestamp)"),
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
	}

	// MARK: - Channel labels

	/// Persisted on `node.powerChannelLabels` (SwiftData) rather than `UserDefaults` so labels are
	/// deleted along with the node instead of accumulating indefinitely after it's forgotten.
	private func loadChannelLabels() -> [String] {
		let stored = node.powerChannelLabels
		return (0..<3).map { index in index < stored.count ? stored[index] : "" }
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
		let custom = index < channelLabels.count ? channelLabels[index].trimmingCharacters(in: .whitespaces) : ""
		return custom.isEmpty ? String(format: "Channel %d".localized, index + 1) : custom
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
