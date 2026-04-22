//
//  WifiProvisioningView.swift
//  Meshtastic
//
//  Full-screen sheet that guides the user through provisioning a mPWRD-OS device
//  (running nymea-networkmanager) onto Wi-Fi via Bluetooth.
//
//  State is driven entirely by NymeaProvisioningManager.state.
//

import SwiftUI

// MARK: - Activity row

private struct ActivityRow: View {
	let systemImage: String
	let label: String

	var body: some View {
		HStack(spacing: 16) {
			Image(systemName: systemImage)
				.font(.system(size: 32))
				.symbolRenderingMode(.hierarchical)
				.symbolEffect(.variableColor.reversing.cumulative,
							  options: .repeat(20).speed(2))
				.foregroundColor(.accentColor)
				.frame(width: 44)
			Text(label)
				.font(.title3)
				.foregroundColor(.primary)
		}
		.padding()
	}
}

// MARK: - Device list row

private struct DeviceRow: View {
	let device: NymeaDiscoveredDevice
	let onSelect: (NymeaDiscoveredDevice) -> Void

	var body: some View {
		Button { onSelect(device) } label: {
			HStack(spacing: 12) {
				Image(systemName: "wifi.router")
					.font(.title2)
					.foregroundColor(.accentColor)
					.frame(width: 36)

				VStack(alignment: .leading, spacing: 2) {
					Text(device.name)
						.font(.body)
						.foregroundColor(.primary)
					Text("RSSI \(device.rssi) dBm")
						.font(.caption2)
						.foregroundColor(.secondary)
				}

				Spacer()

				// Simple signal indicator reusing the nymea signal-bars logic
				SignalBarsView(bars: rssiToBars(device.rssi), color: .accentColor)
					.frame(height: 18)
			}
			.padding(.vertical, 4)
		}
	}

	private func rssiToBars(_ rssi: Int) -> Int {
		switch rssi {
		case -50...0:   return 4
		case -65 ... -51: return 3
		case -75 ... -66: return 2
		case -90 ... -76: return 1
		default:         return 0
		}
	}
}

// MARK: - Signal bars (shared with WifiNetworkListView)

struct SignalBarsView: View {
	let bars: Int
	let color: Color

	var body: some View {
		HStack(alignment: .bottom, spacing: 2) {
			ForEach(1...4, id: \.self) { index in
				RoundedRectangle(cornerRadius: 1.5)
					.frame(width: 5, height: CGFloat(index) * 4 + 2)
					.foregroundColor(index <= bars ? color : color.opacity(0.2))
			}
		}
	}
}

// MARK: - WifiProvisioningView

struct WifiProvisioningView: View {

	@EnvironmentObject private var provisioning: NymeaProvisioningManager
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			Group {
				switch provisioning.state {

				case .idle:
					idleView

				case .scanningForDevices:
					waitingView(
						icon: "antenna.radiowaves.left.and.right",
						message: "Searching for mPWRD-OS devices…"
					)

				case .selectingDevice(let devices):
					deviceSelectionView(devices: devices)

			case .connectingBLE:
				waitingView(icon: "dot.radiowaves.right", message: "Connecting via Bluetooth…")

				case .checkingNetworkState:
					waitingView(icon: "network", message: "Checking device network state…")

				case .scanning:
					waitingView(icon: "wifi.router", message: "Scanning for Wi-Fi networks…")

				case .awaitingNetworkSelection(let networks):
					networkSelectionView(networks: networks)

				case .sendingCredentials(let ssid):
					waitingView(icon: "wifi", message: "Connecting to \"\(ssid)\"…")

				case .retrievingIPAddress:
					waitingView(icon: "network.badge.shield.half.filled", message: "Retrieving IP address…")

				case .success(let ip):
					successView(ipAddress: ip)

				case .failed(let message):
					failureView(message: message)
				}
			}
			.navigationTitle("Wi-Fi Provisioning")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					cancelOrDoneButton
				}
			}
		}
	}

	// MARK: - Sub-views

	@ViewBuilder
	private var idleView: some View {
		VStack(spacing: 32) {
			Spacer()

			Image(systemName: "wifi.router.fill")
				.font(.system(size: 72))
				.symbolRenderingMode(.hierarchical)
				.foregroundColor(.accentColor)

			VStack(spacing: 8) {
				Text("Set Up Wi-Fi")
					.font(.title2.bold())
				Text("Connect your mPWRD-OS device to a Wi-Fi network via Bluetooth.")
					.multilineTextAlignment(.center)
					.font(.body)
					.foregroundColor(.secondary)
					.padding(.horizontal, 32)
			}

			Button {
				provisioning.startProvisioning()
			} label: {
				Label("Find Device", systemImage: "antenna.radiowaves.left.and.right")
					.font(.headline)
					.frame(maxWidth: .infinity)
					.padding()
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.capsule)
			.padding(.horizontal, 32)

			Spacer()
			Spacer()
		}
	}

	@ViewBuilder
	private func waitingView(icon: String, message: String) -> some View {
		VStack(spacing: 24) {
			Spacer()
			ActivityRow(systemImage: icon, label: message)
			Spacer()
		}
	}

	@ViewBuilder
	private func deviceSelectionView(devices: [NymeaDiscoveredDevice]) -> some View {
		List {
			Section {
				ForEach(devices) { device in
					DeviceRow(device: device) { selected in
						provisioning.selectDevice(selected)
					}
				}
			} header: {
				Label("Nearby Devices", systemImage: "antenna.radiowaves.left.and.right")
					.font(.headline)
					.textCase(nil)
			} footer: {
				HStack(spacing: 6) {
					ProgressView()
					Text("Scanning…")
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
		}
		.listStyle(.insetGrouped)
	}

	@ViewBuilder
	private func networkSelectionView(networks: [NymeaWifiNetwork]) -> some View {
		WifiNetworkListView(
			networks: networks,
			onSelectNetwork: { network, password in
				provisioning.selectNetwork(network, password: password)
			},
			onSelectHiddenNetwork: { ssid, password in
				provisioning.selectHiddenNetwork(ssid: ssid, password: password)
			}
		)
	}

	@ViewBuilder
	private func successView(ipAddress: String) -> some View {
		VStack(spacing: 0) {
			Spacer()

			Image(systemName: "checkmark.circle.fill")
				.font(.system(size: 72))
				.symbolRenderingMode(.hierarchical)
				.foregroundColor(.green)
				.padding(.bottom, 20)

			Text("Device Connected")
				.font(.title2.bold())
				.padding(.bottom, 8)

			Text("Your mPWRD-OS device has joined the Wi-Fi network.")
				.multilineTextAlignment(.center)
				.font(.body)
				.foregroundColor(.secondary)
				.padding(.horizontal, 32)
				.padding(.bottom, 32)

			// IP address card
			VStack(alignment: .leading, spacing: 12) {
				Text("IP Address")
					.font(.caption)
					.foregroundColor(.secondary)

				HStack {
					Text(ipAddress)
						.font(.system(.title3, design: .monospaced))
					Spacer()
					Button {
						UIPasteboard.general.string = ipAddress
					} label: {
						Label("Copy", systemImage: "doc.on.doc")
							.labelStyle(.iconOnly)
							.font(.title3)
					}
					.tint(.accentColor)
				}

				Divider()

				Text("Complete device setup via SSH:")
					.font(.caption)
					.foregroundColor(.secondary)

				Text("ssh mpwrd@\(ipAddress)")
					.font(.system(.caption, design: .monospaced))
					.padding(8)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(Color(.secondarySystemBackground))
					.cornerRadius(6)
			}
			.padding()
			.background(Color(.systemBackground))
			.cornerRadius(12)
			.shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
			.padding(.horizontal, 24)

			Spacer()
			Spacer()

			Button {
				provisioning.reset()
				dismiss()
			} label: {
				Text("Done")
					.font(.headline)
					.frame(maxWidth: .infinity)
					.padding()
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.capsule)
			.padding(.horizontal, 32)
			.padding(.bottom, 24)
		}
	}

	@ViewBuilder
	private func failureView(message: String) -> some View {
		VStack(spacing: 24) {
			Spacer()

			Image(systemName: "wifi.exclamationmark")
				.font(.system(size: 64))
				.symbolRenderingMode(.hierarchical)
				.foregroundColor(.red)

			VStack(spacing: 8) {
				Text("Provisioning Failed")
					.font(.title2.bold())
				Text(message)
					.multilineTextAlignment(.center)
					.font(.body)
					.foregroundColor(.secondary)
					.padding(.horizontal, 32)
			}

			Button {
				provisioning.reset()
			} label: {
				Label("Try Again", systemImage: "arrow.clockwise")
					.font(.headline)
					.frame(maxWidth: .infinity)
					.padding()
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.capsule)
			.padding(.horizontal, 32)

			Spacer()
		}
	}

	@ViewBuilder
	private var cancelOrDoneButton: some View {
		if case .success = provisioning.state {
			Button("Done") {
				provisioning.reset()
				dismiss()
			}
		} else {
			Button("Cancel") {
				provisioning.cancel()
				dismiss()
			}
		}
	}
}
