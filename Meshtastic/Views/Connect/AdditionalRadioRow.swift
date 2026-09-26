//
//  AdditionalRadioRow.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftData
import SwiftUI

/// A radio connected alongside the focused one (feature 021), shown on the Connect tab.
///
/// "Focus" makes it the focused radio: the one whose settings the app shows, and the default
/// for sending. Every connected radio keeps receiving into the shared store either way, and
/// runs its own MQTT client proxy when its config asks for one.
struct AdditionalRadioRow: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	let device: Device
	@Binding var isSwitchingRadio: Bool
	@State private var batteryLevel: Int32?
	@State private var unreadDirectMessages = 0

	private var isConnecting: Bool {
		device.connectionState == .connecting
	}

	/// The radio's latest battery reading and its unread direct messages. On an interval rather
	/// than in `body`, for the same reason as the focused radio's battery on the Connect tab.
	private func refreshStatus() {
		guard let radioNum = device.num else { return }
		let deviceMetrics: Int32 = 0
		var latest = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == radioNum && $0.metricsType == deviceMetrics },
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		latest.fetchLimit = 1
		let level = (try? context.fetch(latest).first)?.batteryLevel ?? 0
		batteryLevel = level > 0 ? level : nil
		// Addressed to this radio: a direct message it received.
		let unread = FetchDescriptor<MessageEntity>(predicate: #Predicate<MessageEntity> {
			$0.toNum == radioNum && $0.read == false && $0.isEmoji == false
		})
		unreadDirectMessages = (try? context.fetchCount(unread)) ?? 0
	}

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: isConnecting ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.circle.fill")
				.font(.title2)
				.foregroundStyle(isConnecting ? Color.orange : Color.green)
				.symbolEffect(.pulse, isActive: isConnecting)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text(device.longName ?? device.name)
					.font(.headline)
				HStack(spacing: 6) {
					TransportIcon(transportType: device.transportType)
					Text(isConnecting ? "Connecting…" : "Connected")
						.font(.caption)
						.foregroundStyle(.secondary)
					if let shortName = device.shortName {
						Text(shortName)
							.font(.caption.monospaced())
							.foregroundStyle(.secondary)
					}
				}
				// T081: battery, signal and unread direct messages, like the focused radio's row.
				HStack(spacing: 10) {
					if let batteryLevel {
						BatteryCompact(batteryLevel: batteryLevel, font: .caption, iconFont: .callout, color: .accentColor)
					}
					if let rssi = device.rssi, device.transportType == .ble {
						Label("\(rssi) dBm", systemImage: "cellularbars")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					if unreadDirectMessages > 0 {
						Label("\(unreadDirectMessages)", systemImage: "bubble.left.fill")
							.font(.caption)
							.foregroundStyle(.secondary)
							.accessibilityLabel(String.localizedStringWithFormat("%d unread direct messages".localized, unreadDirectMessages))
					}
				}
			}
			.task(id: device.num) {
				while !Task.isCancelled {
					refreshStatus()
					try? await Task.sleep(for: .seconds(15))
				}
			}
			Spacer()
			Menu {
				Button {
					Task {
						await performRadioSwitch(device, isSwitchingRadio: $isSwitchingRadio, accessoryManager: accessoryManager)
					}
				} label: {
					Label("Focus This Radio", systemImage: "scope")
				}
				.disabled(isConnecting)
				Button(role: .destructive) {
					Task { await accessoryManager.disconnectAdditionalRadio(device.id, byUser: true) }
				} label: {
					Label("Disconnect", systemImage: "xmark.circle")
				}
			} label: {
				Image(systemName: "ellipsis.circle")
					.font(.title3)
			}
			.accessibilityLabel("Actions for \(device.longName ?? device.name)")
		}
	}
}
