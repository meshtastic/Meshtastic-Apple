//
//  DeviceConnectionView.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import SwiftUI

/// View for scanning and connecting to a Meshtastic BLE radio directly
/// from the Apple Watch (no phone required).
struct DeviceConnectionView: View {

	@ObservedObject var bleManager: WatchBLEManager

	var body: some View {
		Group {
			switch bleManager.connectionState {
			case .disconnected:
				disconnectedView
			case .connecting:
				connectingView
			case .connected:
				connectedView
			}
		}
		.navigationTitle("Radio")
	}

	// MARK: - Disconnected

	@ViewBuilder
	private var disconnectedView: some View {
		VStack(spacing: 8) {
			if bleManager.discoveredDevices.isEmpty && !bleManager.isScanning {
				VStack(spacing: 8) {
					Image(systemName: "antenna.radiowaves.left.and.right.slash")
						.font(.title2)
						.foregroundStyle(.secondary)
					Text("No radio connected")
						.font(.headline)
					Text("Scan to find nearby Meshtastic radios.")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}
				.padding()
			}

			if bleManager.isScanning && bleManager.discoveredDevices.isEmpty {
				VStack(spacing: 8) {
					ProgressView()
					Text("Scanning…")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding()
			}

			if !bleManager.discoveredDevices.isEmpty {
				List(bleManager.discoveredDevices) { device in
					Button {
						bleManager.connect(to: device)
					} label: {
						HStack {
							VStack(alignment: .leading, spacing: 2) {
								Text(device.name)
									.font(.system(size: 14, weight: .semibold))
									.lineLimit(1)
								Text("\(device.rssi) dBm")
									.font(.system(size: 11))
									.foregroundStyle(.secondary)
							}
							Spacer()
							signalIcon(rssi: device.rssi)
						}
					}
				}
			}

			Button {
				if bleManager.isScanning {
					bleManager.stopScanning()
				} else {
					bleManager.startScanning()
				}
			} label: {
				Label(bleManager.isScanning ? "Stop" : "Scan",
					  systemImage: bleManager.isScanning ? "stop.fill" : "magnifyingglass")
			}
			.buttonStyle(.borderedProminent)
			.tint(bleManager.isScanning ? .red : .accentColor)
		}
	}

	// MARK: - Connecting

	@ViewBuilder
	private var connectingView: some View {
		VStack(spacing: 8) {
			ProgressView()
			Text("Connecting…")
				.font(.headline)
			if let name = bleManager.connectedDeviceName {
				Text(name)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding()
	}

	// MARK: - Connected

	@ViewBuilder
	private var connectedView: some View {
		VStack(spacing: 8) {
			Image(systemName: "checkmark.circle.fill")
				.font(.title2)
				.foregroundStyle(.green)
			Text("Connected")
				.font(.headline)
			if let name = bleManager.connectedDeviceName {
				Text(name)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Text("\(bleManager.nodes.count) nodes")
				.font(.caption2)
				.foregroundStyle(.secondary)

			Button(role: .destructive) {
				bleManager.disconnect()
			} label: {
				Label("Disconnect", systemImage: "xmark.circle")
			}
			.buttonStyle(.bordered)
		}
		.padding()
	}

	// MARK: - Helpers

	@ViewBuilder
	private func signalIcon(rssi: Int) -> some View {
		Image(systemName: rssi > -85 ? "wifi" : "wifi.exclamationmark")
			.font(.system(size: 12))
			.foregroundStyle(rssi > -65 ? .green : (rssi > -85 ? .yellow : .red))
	}
}
