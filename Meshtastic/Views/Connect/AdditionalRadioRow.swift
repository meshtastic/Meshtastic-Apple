//
//  AdditionalRadioRow.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

/// A radio connected alongside the focused one (feature 021), shown on the Connect tab.
///
/// "Focus" makes it the focused radio: settings, MQTT, location sharing and sending go through
/// the focused radio. Every connected radio keeps receiving into the shared store either way.
struct AdditionalRadioRow: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	let device: Device
	@Binding var isSwitchingRadio: Bool

	private var isConnecting: Bool {
		device.connectionState == .connecting
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
					Task { await accessoryManager.disconnectAdditionalRadio(device.id) }
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
