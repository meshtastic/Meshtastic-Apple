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

// MARK: - Copy toast

private struct CopyToast: View {
	let message: String

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "checkmark.circle.fill")
				.foregroundColor(.green)
			Text(message)
				.font(.subheadline)
				.foregroundColor(.primary)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
		.background(.regularMaterial, in: Capsule())
		.shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
	}
}

// MARK: - Credential row

private struct CredentialRow: View {
	let label: String
	let value: String
	let onCopy: () -> Void

	var body: some View {
		HStack {
			Text(label)
				.font(.caption)
				.foregroundColor(.secondary)
				.frame(width: 80, alignment: .leading)
			Text(value)
				.font(.system(.body, design: .monospaced))
			Spacer()
			Button(action: onCopy) {
				Image(systemName: "doc.on.doc")
					.font(.body)
			}
			.tint(.accentColor)
			.buttonStyle(.borderless)
		}
	}
}

// MARK: - WifiProvisioningView

struct WifiProvisioningView: View {

	@EnvironmentObject private var provisioning: NymeaProvisioningManager
	@Environment(\.dismiss) private var dismiss

	@State private var toastMessage: String?
	@State private var noSSHClientNotice = false

	/// If supplied, the sheet skips the idle/scan/picker stages and immediately
	/// connects to the given device. Used when the user taps a nymea device from
	/// the Connect list.
	let preselectedDevice: NymeaDiscoveredDevice?

	private static let defaultSSHUser = "root"
	private static let defaultSSHPassword = "1234"

	init(preselectedDevice: NymeaDiscoveredDevice? = nil) {
		self.preselectedDevice = preselectedDevice
	}

	var body: some View {
		NavigationStack {
			Group {
				switch provisioning.state {

				case .idle:
					// When we have a preselected device, the .task below will kick off
					// provisioning, but the body renders before .task fires. Show a
					// neutral "Connecting…" view in that interim instead of flashing
					// the "Find Device" idle screen.
					if preselectedDevice != nil {
						waitingView(icon: "dot.radiowaves.right", message: "Connecting via Bluetooth…")
					} else {
						idleView
					}

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
			.task {
				if let device = preselectedDevice, provisioning.state == .idle {
					provisioning.beginProvisioning(with: device)
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
		ZStack(alignment: .bottom) {
			ScrollView {
				VStack(spacing: 24) {
					Image(systemName: "checkmark.circle.fill")
						.font(.system(size: 72))
						.symbolRenderingMode(.hierarchical)
						.foregroundColor(.green)
						.padding(.top, 24)

					VStack(spacing: 8) {
						Text("Device Connected")
							.font(.title2.bold())
						Text("Your mPWRD-OS device has joined the Wi-Fi network.")
							.multilineTextAlignment(.center)
							.font(.body)
							.foregroundColor(.secondary)
							.padding(.horizontal, 32)
					}

					// IP address card
					VStack(alignment: .leading, spacing: 8) {
						Text("IP Address")
							.font(.caption)
							.foregroundColor(.secondary)
						HStack {
							Text(ipAddress)
								.font(.system(.title3, design: .monospaced))
							Spacer()
							Button {
								copy(ipAddress, label: "IP address")
							} label: {
								Image(systemName: "doc.on.doc")
									.font(.title3)
							}
							.tint(.accentColor)
							.buttonStyle(.borderless)
						}
					}
					.padding()
					.background(Color(.systemBackground))
					.cornerRadius(12)
					.shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
					.padding(.horizontal, 24)

					// SSH setup card
					VStack(alignment: .leading, spacing: 16) {
						VStack(alignment: .leading, spacing: 4) {
							Text("Complete Device Setup")
								.font(.headline)
							Text("Sign in over SSH to change the default username and password.")
								.font(.caption)
								.foregroundColor(.secondary)
						}

						VStack(spacing: 8) {
							CredentialRow(
								label: "Username",
								value: Self.defaultSSHUser
							) {
								copy(Self.defaultSSHUser, label: "Username")
							}
							Divider()
							CredentialRow(
								label: "Password",
								value: Self.defaultSSHPassword
							) {
								copy(Self.defaultSSHPassword, label: "Password")
							}
							Divider()
							HStack {
								Text("ssh \(Self.defaultSSHUser)@\(ipAddress)")
									.font(.system(.caption, design: .monospaced))
									.lineLimit(1)
									.truncationMode(.middle)
								Spacer()
								Button {
									copy("ssh \(Self.defaultSSHUser)@\(ipAddress)", label: "Command")
								} label: {
									Image(systemName: "doc.on.doc")
										.font(.body)
								}
								.tint(.accentColor)
								.buttonStyle(.borderless)
							}
							.padding(8)
							.background(Color(.secondarySystemBackground))
							.cornerRadius(6)
						}

						Button {
							launchSSH(ipAddress: ipAddress)
						} label: {
							Label("Open SSH Client", systemImage: "terminal")
								.font(.headline)
								.frame(maxWidth: .infinity)
								.padding(.vertical, 8)
						}
						.buttonStyle(.borderedProminent)
						.buttonBorderShape(.capsule)

						if noSSHClientNotice {
							Text("No SSH client found. We'll open the App Store so you can install one.")
								.font(.caption)
								.foregroundColor(.secondary)
								.multilineTextAlignment(.center)
								.frame(maxWidth: .infinity)
						}
					}
					.padding()
					.background(Color(.systemBackground))
					.cornerRadius(12)
					.shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
					.padding(.horizontal, 24)

					Spacer(minLength: 100)
				}
			}

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
			.background(
				LinearGradient(
					colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
					startPoint: .top,
					endPoint: .bottom
				)
				.allowsHitTesting(false)
			)

			if let toastMessage {
				CopyToast(message: toastMessage)
					.padding(.bottom, 100)
					.transition(.opacity.combined(with: .move(edge: .bottom)))
			}
		}
		.animation(.easeInOut(duration: 0.2), value: toastMessage)
		.animation(.easeInOut(duration: 0.2), value: noSSHClientNotice)
	}

	// MARK: - SSH helpers

	private func sshURL(ip: String, user: String = WifiProvisioningView.defaultSSHUser) -> URL? {
		URL(string: "ssh://\(user)@\(ip)")
	}

	private func appStoreSSHSearchURL() -> URL? {
		URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=ssh")
	}

	private func launchSSH(ipAddress: String) {
		guard let url = sshURL(ip: ipAddress) else { return }
		if UIApplication.shared.canOpenURL(url) {
			noSSHClientNotice = false
			UIApplication.shared.open(url)
		} else {
			noSSHClientNotice = true
			if let storeURL = appStoreSSHSearchURL() {
				UIApplication.shared.open(storeURL)
			}
		}
	}

	private func copy(_ value: String, label: String) {
		UIPasteboard.general.string = value
		toastMessage = "\(label) copied"
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		Task {
			try? await Task.sleep(nanoseconds: 1_500_000_000)
			await MainActor.run {
				if toastMessage == "\(label) copied" {
					toastMessage = nil
				}
			}
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
