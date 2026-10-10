//
//  OfflineRadioRow.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

/// One of the user's radios that's off (feature 021, W-02): on its window's Connect tab, and in
/// the Mac's Connect window, which can also open its window. Connect connects it as picking it
/// from the radios found does, once discovery sees it; Remove Radio asks first, through the list's
/// confirmation (`askToRemoveRadio`).
struct OfflineRadioRow: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@EnvironmentObject private var router: Router
	@Environment(\.windowRadio) private var windowRadio
	@Environment(\.selectWindowRadio) private var selectWindowRadio
	@Environment(\.askToRemoveRadio) private var askToRemoveRadio
	let radio: OfflineRadio
	@Binding var isSwitchingRadio: Bool
	/// Opens its window (the Mac's Connect window); also once Connect connects it.
	var open: (() -> Void)?
	/// Why Connect failed, for the list to show: this row goes away as the connect starts, so it
	/// can't show it itself (review V27, minor 2). Nil where the window shows its radio's error
	/// already (`linkStatus(for:)`'s last error, on the Connect tab).
	var connectFailed: ((String) -> Void)?
	@State private var isStartingConnect = false

	private var device: Device? {
		accessoryManager.connectableDevice(radio.deviceId)
	}

	/// It dropped and is being tried again.
	private var isBeingBroughtBack: Bool {
		accessoryManager.additionalRadioReconnects[radio.deviceId] != nil
	}

	private var isAtRadioLimit: Bool {
		accessoryManager.connectedRadioCount > 0 && !accessoryManager.canConnectAnotherRadio
	}

	private var status: LocalizedStringKey {
		if isBeingBroughtBack {
			return "Reconnecting…"
		}
		return device == nil ? "Not connected · Looking for it…" : "Not connected"
	}

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: "antenna.radiowaves.left.and.right.slash")
				.font(.title2)
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text(radio.name)
					.font(.headline)
				HStack(spacing: 6) {
					if let device {
						TransportIcon(transportType: device.transportType)
					}
					Text(status)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Spacer()
			// Borderless, so each is its own click target in a list row.
			if let open {
				Button("Open", action: open)
					.buttonStyle(.borderless)
					.accessibilityLabel(Text("Open \(radio.name)"))
			}
			Button("Connect", action: connect)
				.buttonStyle(.borderless)
				.disabled(device == nil || isBeingBroughtBack || isStartingConnect || isAtRadioLimit)
				.accessibilityLabel(Text("Connect \(radio.name)"))
			if let askToRemoveRadio, accessoryManager.canRemoveRadio(radio.nodeNum) {
				Button("Remove", role: .destructive) {
					askToRemoveRadio(RadioToRemove(nodeNum: radio.nodeNum, name: radio.name))
				}
				.buttonStyle(.borderless)
				.accessibilityLabel(Text("Remove \(radio.name)"))
			}
		}
		.padding(.vertical, 4)
	}

	private func connect() {
		guard let device else { return }
		isStartingConnect = true
		Task {
			defer { isStartingConnect = false }
			do {
				try await accessoryManager.connectPickedRadio(device, isSwitchingRadio: $isSwitchingRadio, router: router, windowRadio: windowRadio, selectWindowRadio: selectWindowRadio)
				if accessoryManager.isRadioConnected(device.id) {
					open?()
				}
			} catch {
				connectFailed?(error.localizedDescription)
			}
		}
	}
}
