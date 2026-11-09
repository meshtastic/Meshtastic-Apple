//
//  HostMetricsLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import SwiftUI
@preconcurrency import SwiftData
import OSLog

/// The host metrics a Linux meshtasticd node has sent: uptime, free memory, load and free
/// disk space, newest first.
struct HostMetricsLog: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Bindable var node: NodeInfoEntity
	@State private var readings: [TelemetryEntity] = []
	@State private var isPresentingClearLogConfirm = false

	private var canRequest: Bool {
		accessoryManager.isConnected && accessoryManager.activeDeviceNum.map { $0 != node.num } == true
	}

	var body: some View {
		List {
			if readings.isEmpty {
				ContentUnavailableView(
					"No Host Metrics",
					systemImage: "server.rack",
					description: Text("Linux nodes running meshtasticd send their uptime, free memory, load and free disk space.")
				)
			}
			ForEach(readings) { reading in
				Section {
					HostMetricsReading(metrics: reading)
				} header: {
					Text(reading.time?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Unknown Age"))
				}
			}
		}
		.safeAreaInset(edge: .bottom) {
			HStack {
				if canRequest {
					TelemetryRequestButton(
						node: node,
						kind: .host,
						style: .labeled(title: "Request", cooldownTitle: "Wait")
					)
				}
				if !readings.isEmpty {
					Button(role: .destructive) {
						isPresentingClearLogConfirm = true
					} label: {
						Label("Clear Log", systemImage: "trash")
					}
					.confirmationDialog(
						"Are you sure?",
						isPresented: $isPresentingClearLogConfirm,
						titleVisibility: .visible
					) {
						Button("Delete all host metrics?", role: .destructive) {
							Task { @MainActor in
								if await MeshPackets.shared.clearTelemetry(destNum: node.num, metricsType: 5) {
									refresh()
								} else {
									Logger.data.error("Clear Host Metrics Log Failed")
								}
							}
						}
					}
				}
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.roundedRectangle)
			.controlSize(.large)
			.padding(.vertical, 8)
			.frame(maxWidth: .infinity)
			.background(.bar)
		}
		.navigationTitle("Host Metrics Log")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear(perform: refresh)
		.onChange(of: node.lastHeard) {
			refresh()
		}
	}

	private func refresh() {
		let nodeNum = node.num
		let metricsType: Int32 = 5
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType),
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 500
		readings = (try? context.fetch(descriptor)) ?? []
	}
}

/// One host metrics reading, as rows of a list section.
struct HostMetricsReading: View {
	let metrics: TelemetryEntity

	var body: some View {
		if let uptime = metrics.uptimeSeconds {
			LabeledContent("Uptime") {
				Text(Duration.seconds(Int64(uptime)).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
			}
		}
		if let free = metrics.hostFreeMemoryBytes {
			LabeledContent("Free Memory") {
				Text(free.formatted(.byteCount(style: .memory)))
			}
		}
		if let load1 = metrics.hostLoad1, let load5 = metrics.hostLoad5, let load15 = metrics.hostLoad15 {
			LabeledContent("Load Average") {
				Text(verbatim: [load1, load5, load15].map { (Double($0) / 100).formatted(.number.precision(.fractionLength(2))) }.joined(separator: "  "))
			}
			.accessibilityValue(String(localized: "1 minute \(Double(load1) / 100), 5 minutes \(Double(load5) / 100), 15 minutes \(Double(load15) / 100)", comment: "VoiceOver value for a host's load averages"))
		}
		if let disk = metrics.hostDiskFree1Bytes {
			LabeledContent("Free Disk Space") {
				Text(disk.formatted(.byteCount(style: .file)))
			}
		}
		if let disk = metrics.hostDiskFree2Bytes {
			LabeledContent("Free Disk Space 2") {
				Text(disk.formatted(.byteCount(style: .file)))
			}
		}
		if let disk = metrics.hostDiskFree3Bytes {
			LabeledContent("Free Disk Space 3") {
				Text(disk.formatted(.byteCount(style: .file)))
			}
		}
		if let note = metrics.hostUserString, !note.isEmpty {
			Text(note)
				.font(.callout)
				.foregroundStyle(.secondary)
		}
	}
}
