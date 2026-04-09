//
//  ChannelForm.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 3/17/24.
//

import SwiftUI
import MapKit

struct ChannelForm: View {

	@ObservedObject var channel: ChannelEntity
	@EnvironmentObject var accessoryManager: AccessoryManager

	/// UI-only state derived from channel data on appear
	@State private var channelKey = ""
	@State private var channelKeySize = 16
	@State private var positionsEnabled = true
	@State private var preciseLocation = true
	@State private var hasValidKey = true
	@State private var supportedVersion = true

	private let minimumVersion = "2.2.24"

	var body: some View {
		NavigationStack {
			Form {
				Section(header: Text("Channel Details")) {
					HStack {
						Text("Name")
						Spacer()
						TextField(
							"Channel Name",
							text: Binding(
								get: { channel.name ?? "" },
								set: { channel.name = $0 }
							)
						)
						.disableAutocorrection(true)
						.keyboardType(.alphabet)
						.foregroundColor(Color.gray)
						.onChange(of: channel.name) { _, name in
							var trimmed = (name ?? "").replacingOccurrences(of: " ", with: "")
							while trimmed.utf8.count > 11 { trimmed = String(trimmed.dropLast()) }
							if trimmed != name { channel.name = trimmed }
						}
					}
					HStack {
						Picker("Key Size", selection: $channelKeySize) {
							Text("Empty").tag(0)
							Text("Default").tag(-1)
							Text("1 byte").tag(1)
							Text("128 bit").tag(16)
							Text("256 bit").tag(32)
						}
						.pickerStyle(DefaultPickerStyle())
						Spacer()
						Button {
							if channelKeySize == -1 {
								channelKey = "AQ=="
							} else if channelKeySize > 0 {
								channelKey = generateChannelKey(size: channelKeySize)
							} else {
								channelKey = ""
							}
							channel.psk = Data(base64Encoded: channelKey)
						} label: {
							Image(systemName: "lock.rotation")
								.font(.title)
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.small)
					}
					HStack(alignment: .center) {
						Text("Key")
						Spacer()
						TextField(
							"Key",
							text: $channelKey,
							axis: .vertical
						)
						.padding(6)
						.disableAutocorrection(true)
						.keyboardType(.alphabet)
						.foregroundColor(Color.gray)
						.textSelection(.enabled)
						.background(
							RoundedRectangle(cornerRadius: 10.0)
								.stroke(
									hasValidKey ? Color.clear : Color.red,
									lineWidth: 2.0)
						)
						.onChange(of: channelKey) { _, key in
							let data = Data(base64Encoded: key) ?? Data()
							hasValidKey = data.count == channelKeySize || channelKeySize == -1
							channel.psk = data.isEmpty ? nil : data
						}
						.disabled(channelKeySize <= 0)
					}
					HStack {
						if channel.role == 1 {
							Picker("Channel Role", selection: Binding(
								get: { Int(channel.role) },
								set: { channel.role = Int32($0) }
							)) {
								Text("Primary").tag(1)
							}
							.pickerStyle(.automatic)
							.disabled(true)
						} else {
							Text("Channel Role")
							Spacer()
							Picker("Channel Role", selection: Binding(
								get: { Int(channel.role) },
								set: { channel.role = Int32($0) }
							)) {
								Text("Disabled").tag(0)
								Text("Secondary").tag(2)
							}
							.pickerStyle(.segmented)
						}
					}
				}

				Section(header: Text("Position")) {
					VStack(alignment: .leading) {
						Toggle(isOn: $positionsEnabled) {
							Label(
								channel.role == 1 ? "Positions Enabled" : "Allow Position Requests",
								systemImage: positionsEnabled ? "mappin" : "mappin.slash"
							)
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.disabled(!supportedVersion)
					}

					if positionsEnabled {
						if channelKey != "AQ==" && channelKeySize > 1 && channel.role > 0 {
							VStack(alignment: .leading) {
								Toggle(isOn: $preciseLocation) {
									Label("Precise Location", systemImage: "scope")
								}
								.toggleStyle(SwitchToggleStyle(tint: .accentColor))
								.disabled(!supportedVersion)
								.listRowSeparator(.visible)
							}
						}
						if !preciseLocation {
							VStack(alignment: .leading) {
								Label("Approximate Location", systemImage: "location.slash.circle.fill")
								Slider(
									value: Binding(
										get: { Double(channel.positionPrecision) },
										set: { channel.positionPrecision = Int32($0) }
									),
									in: 12...15,
									step: 1
								) {
								} minimumValueLabel: {
									Image(systemName: "plus")
								} maximumValueLabel: {
									Image(systemName: "minus")
								}
								Text(PositionPrecision(rawValue: Int(channel.positionPrecision))?.description ?? "")
									.foregroundColor(.gray)
									.font(.callout)
							}
						}
					}
				}

				Section(header: Text("MQTT")) {
					Toggle(isOn: Binding(
						get: { channel.uplinkEnabled },
						set: { channel.uplinkEnabled = $0 }
					)) {
						Label("Uplink Enabled", systemImage: "arrowshape.up")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: Binding(
						get: { channel.downlinkEnabled },
						set: { channel.downlinkEnabled = $0 }
					)) {
						Label("Downlink Enabled", systemImage: "arrowshape.down")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
			}
			.onFirstAppear {
				supportedVersion = accessoryManager.checkIsVersionSupported(forVersion: minimumVersion)
				channelKey = channel.psk?.base64EncodedString() ?? ""
				channelKeySize = keySizeFromPsk(channel.psk)

				if !supportedVersion {
					if channel.role == 1 {
						positionsEnabled = true
						if channelKey == "AQ==" {
							preciseLocation = false
							channel.positionPrecision = 14
						} else {
							preciseLocation = true
							channel.positionPrecision = 32
						}
					} else {
						positionsEnabled = false
						preciseLocation = false
						channel.positionPrecision = 0
					}
				} else {
					positionsEnabled = channel.positionPrecision > 0
					if channelKey == "AQ==" {
						preciseLocation = false
						let p = channel.positionPrecision
						if p > 0 && (p < 11 || p > 14) {
							channel.positionPrecision = 14
						}
					} else {
						preciseLocation = channel.positionPrecision == 32
					}
				}
			}
			.onChange(of: channelKeySize) { _, size in
				if size == -1 {
					channelKey = "AQ=="
				} else if size > 0 {
					channelKey = generateChannelKey(size: size)
				} else {
					channelKey = ""
				}
				channel.psk = channelKey.isEmpty ? nil : Data(base64Encoded: channelKey)
			}
			.onChange(of: positionsEnabled) { _, enabled in
				if enabled {
					if channel.positionPrecision == 0 {
						channel.positionPrecision = 15
					}
				} else {
					channel.positionPrecision = 0
					preciseLocation = false
				}
			}
			.onChange(of: preciseLocation) { _, precise in
				if precise {
					if channelKey == "AQ==" || channelKeySize <= 1 {
						preciseLocation = false
					} else {
						channel.positionPrecision = 32
					}
				} else {
					if channel.positionPrecision == 32 {
						channel.positionPrecision = 14
					}
				}
			}
		}
	}

	private func keySizeFromPsk(_ psk: Data?) -> Int {
		let key = psk?.base64EncodedString() ?? ""
		if key.isEmpty { return 0 }
		if key == "AQ==" { return -1 }
		switch key.count {
		case 4: return 1
		case 24: return 16
		case 32: return 24
		case 44: return 32
		default: return 16
		}
	}
}
