//
//  WifiNetworkListView.swift
//  Meshtastic
//
//  Network selection list shown during Wi-Fi provisioning.
//  Displays scanned networks sorted by signal strength with security and signal indicators.
//

import SwiftUI

// MARK: - Network Row

/// A single row in the network list.  Handles protected networks by presenting the
/// password entry sheet internally; open networks fire the callback directly.
private struct NetworkRow: View {
	let network: NymeaWifiNetwork
	/// Called with (network, password) once the user has confirmed.  Password is empty for open networks.
	let onSelect: (NymeaWifiNetwork, String) -> Void

	@State private var showPasswordSheet = false

	var body: some View {
		Button {
			if network.isProtected {
				showPasswordSheet = true
			} else {
				onSelect(network, "")
			}
		} label: {
			HStack(spacing: 12) {
				Image(systemName: network.isProtected ? "lock.fill" : "lock.open.fill")
					.foregroundColor(network.isProtected ? .secondary : .green)
					.frame(width: 20)

				VStack(alignment: .leading, spacing: 2) {
					Text(network.essid)
						.font(.body)
						.foregroundColor(.primary)
					Text("\(network.signal)%")
						.font(.caption2)
						.foregroundColor(.secondary)
				}

				Spacer()

				SignalBarsView(bars: network.signalBars, color: .accentColor)
					.frame(height: 18)
			}
			.padding(.vertical, 4)
		}
		.sheet(isPresented: $showPasswordSheet) {
			PasswordEntrySheet(
				ssid: network.essid,
				isHidden: false,
				onSubmit: { password in
					showPasswordSheet = false
					onSelect(network, password)
				},
				onCancel: { showPasswordSheet = false }
			)
			.presentationDetents([.medium])
			.presentationDragIndicator(.visible)
		}
	}
}

// MARK: - Password Entry Sheet

/// Reusable sheet for entering a Wi-Fi password (or both SSID + password for hidden networks).
struct PasswordEntrySheet: View {
	let ssid: String
	let isHidden: Bool
	/// Called with the entered password (and SSID for hidden networks) when the user taps Join.
	let onSubmit: (String) -> Void
	let onCancel: () -> Void

	@State private var password = ""
	@State private var hiddenSSID = ""
	@FocusState private var passwordFocused: Bool

	var body: some View {
		NavigationStack {
			Form {
				Section {
					if isHidden {
						LabeledContent("Network Name") {
							TextField("SSID", text: $hiddenSSID)
								.multilineTextAlignment(.trailing)
								.autocorrectionDisabled()
								.textInputAutocapitalization(.never)
						}
					} else {
						LabeledContent("Network") {
							Text(ssid).foregroundColor(.secondary)
						}
					}

					LabeledContent("Password") {
						SecureField("Required", text: $password)
							.multilineTextAlignment(.trailing)
							.focused($passwordFocused)
					}
				} footer: {
					Text("Your password is sent directly to the device over Bluetooth and is never stored.")
						.font(.caption)
				}
			}
			.navigationTitle(isHidden ? "Other Network" : "Enter Password")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel", action: onCancel)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Join") {
						// For hidden networks, use hiddenSSID as the identifier conveyed to the callback.
						// The caller receives the password; WifiNetworkListView passes hiddenSSID separately.
						onSubmit(password)
					}
					.disabled(isHidden ? (hiddenSSID.isEmpty || password.isEmpty) : password.isEmpty)
				}
			}
			.onAppear { passwordFocused = true }
		}
	}
}

// MARK: - WifiNetworkListView

/// Displays a sorted list of scanned Wi-Fi networks.  Presents password/SSID entry sheets
/// internally and forwards the confirmed (network + password) or (hidden ssid + password)
/// pair to the parent via callbacks.
struct WifiNetworkListView: View {
	let networks: [NymeaWifiNetwork]
	/// Called with (network, password) when the user confirms a visible network.
	let onSelectNetwork: (NymeaWifiNetwork, String) -> Void
	/// Called with (ssid, password) when the user confirms a hidden network.
	let onSelectHiddenNetwork: (String, String) -> Void

	@State private var showOtherSheet = false
	@State private var hiddenSSID = ""
	@State private var hiddenPassword = ""

	var body: some View {
		List {
			Section {
				ForEach(networks) { network in
					NetworkRow(network: network, onSelect: onSelectNetwork)
				}
			} header: {
				Label("Available Networks", systemImage: "wifi")
					.font(.headline)
					.textCase(nil)
			}

			Section {
				Button {
					showOtherSheet = true
				} label: {
					Label("Other Network…", systemImage: "ellipsis.circle")
				}
			}
		}
		.listStyle(.insetGrouped)
		// Hidden-network sheet — uses a custom binding to capture SSID + password together.
		.sheet(isPresented: $showOtherSheet) {
			HiddenNetworkSheet(
				onSubmit: { ssid, password in
					showOtherSheet = false
					onSelectHiddenNetwork(ssid, password)
				},
				onCancel: { showOtherSheet = false }
			)
			.presentationDetents([.medium])
			.presentationDragIndicator(.visible)
		}
	}
}

// MARK: - Hidden Network Sheet

/// Separate sheet for hidden (non-broadcasting) networks, capturing both SSID and password.
private struct HiddenNetworkSheet: View {
	let onSubmit: (String, String) -> Void
	let onCancel: () -> Void

	@State private var ssid = ""
	@State private var password = ""
	@FocusState private var ssidFocused: Bool

	var body: some View {
		NavigationStack {
			Form {
				Section {
					LabeledContent("Network Name") {
						TextField("SSID", text: $ssid)
							.multilineTextAlignment(.trailing)
							.autocorrectionDisabled()
							.textInputAutocapitalization(.never)
							.focused($ssidFocused)
					}
					LabeledContent("Password") {
						SecureField("Required", text: $password)
							.multilineTextAlignment(.trailing)
					}
				} footer: {
					Text("Your password is sent directly to the device over Bluetooth and is never stored.")
						.font(.caption)
				}
			}
			.navigationTitle("Other Network")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel", action: onCancel)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Join") {
						onSubmit(ssid, password)
					}
					.disabled(ssid.isEmpty || password.isEmpty)
				}
			}
			.onAppear { ssidFocused = true }
		}
	}
}
