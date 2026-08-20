//
//  ChannelForm.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 3/17/24.
//

import SwiftUI
import MapKit

struct ChannelForm: View {

	@Binding var channelIndex: Int32
	@Binding var channelName: String
	@Binding var channelKeySize: Int
	@Binding var channelKey: String
	@Binding var channelRole: Int
	@Binding var uplink: Bool
	@Binding var downlink: Bool
	@Binding var positionPrecision: Double
	@Binding var preciseLocation: Bool
	@Binding var positionsEnabled: Bool
	@Binding var hasChanges: Bool
	@Binding var hasValidKey: Bool
	@Binding var supportedVersion: Bool
	let isHamMode: Bool

	@State private var isPresentingUnencryptedLocationWarning = false
	@State private var isApplyingConfirmedPreciseLocation = false

	private var canEnablePreciseLocation: Bool {
		ChannelPreciseLocationPolicy.canEnablePreciseLocation(
			channelKeySize: channelKeySize,
			channelRole: channelRole,
			isHamMode: isHamMode
		)
	}

	private var requiresPrivacyAcknowledgement: Bool {
		ChannelPreciseLocationPolicy.requiresPrivacyAcknowledgement(
			channelKeySize: channelKeySize,
			isHamMode: isHamMode
		)
	}

	var body: some View {
		Form {
			Section(header: Text("Channel Details")) {
					HStack {
						Text("Name")
						Spacer()
						TextField(
							"Channel Name",
							text: $channelName
						)
						.disableAutocorrection(true)
						.keyboardType(.alphabet)
						.foregroundColor(Color.gray)
						.onChange(of: channelName) {
							channelName = channelName.replacing(" ", with: "")
							var totalBytes = channelName.utf8.count
							// Only mess with the value if it is too big
							while totalBytes > 11 {
								channelName = String(channelName.dropLast())
								totalBytes = channelName.utf8.count
							}
							hasChanges = true
						}
					}
					if ChannelEntity.isReservedModuleName(channelName) {
						Label {
							Text("\"\(channelName)\" is a reserved module channel name and will not appear in the Messages channel list. Pick a different name for a messaging channel.")
								.font(.callout)
						} icon: {
							Image(systemName: "exclamationmark.triangle.fill")
						}
						.foregroundColor(.orange)
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
						.disabled(isHamMode)
						Spacer()
						Button {
							if channelKeySize == -1 {
								channelKey = "AQ=="
							} else {
								let key = generateChannelKey(size: channelKeySize)
								channelKey = key
							}
						} label: {
							Image(systemName: "lock.rotation")
								.font(.title)
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.small)
						.accessibilityLabel(String(localized: "Generate channel key", comment: "VoiceOver label for the generate channel key button"))
						.disabled(isHamMode)
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
									hasValidKey ?
									Color.clear :
										Color.red
									, lineWidth: 2.0)

						)
						.onChange(of: channelKey) {

							let tempKey = Data(base64Encoded: channelKey) ?? Data()
							if tempKey.count == channelKeySize || channelKeySize == -1 {
								hasValidKey = true
							} else {
								hasValidKey = false
							}
							hasChanges = true
						}
						.disabled(isHamMode || channelKeySize <= 0)
					}
					HStack {
						if channelRole == 1 {
							Picker("Channel Role", selection: $channelRole) {
								Text("Primary").tag(1)
							}
							.pickerStyle(.automatic)
							.disabled(true)
						} else {
							Text("Channel Role")
							Spacer()
							Picker("Channel Role", selection: $channelRole) {
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
							Label(channelRole == 1 ? "Positions Enabled" : "Allow Position Requests", systemImage: positionsEnabled ? "mappin" : "mappin.slash")
						}
						.toggleStyle(.switch)
						.disabled(!supportedVersion)
					}

					if positionsEnabled {
						if canEnablePreciseLocation {
							VStack(alignment: .leading) {
								Toggle(isOn: $preciseLocation) {
									Label("Precise Location", systemImage: "scope")
								}
								.toggleStyle(.switch)
								.disabled(!supportedVersion)
								.listRowSeparator(.visible)
							}
						}
						if !preciseLocation {
							VStack(alignment: .leading) {
								Label("Approximate Location", systemImage: "location.slash.circle.fill")

								Slider(value: $positionPrecision, in: 12...15, step: 1) {
								} minimumValueLabel: {
									Image(systemName: "plus")
										.accessibilityHidden(true)
								} maximumValueLabel: {
									Image(systemName: "minus")
										.accessibilityHidden(true)
								}
								.accessibilityLabel(String(localized: "Approximate location precision", comment: "VoiceOver label for the approximate location precision slider"))
								.accessibilityValue(PositionPrecision(rawValue: Int(positionPrecision))?.description ?? "")
								Text(PositionPrecision(rawValue: Int(positionPrecision))?.description ?? "")
									.foregroundColor(.gray)
									.font(.callout)
							}
						}
					}
				}
				Section(header: Text("MQTT")) {
					Toggle(isOn: $uplink) {
						Label("MQTT Uplink Enabled", systemImage: "arrowshape.up")
					}
					.toggleStyle(.switch)
					.listRowSeparator(.visible)

					Toggle(isOn: $downlink) {
						Label("MQTT Downlink Enabled", systemImage: "arrowshape.down")
					}
					.toggleStyle(.switch)
				}
		}
		.onChange(of: channelName) {
			hasChanges = true
		}
		.onChange(of: channelKeySize) {
			if channelKeySize == -1 {
				channelKey = "AQ=="
			} else {
				let key = generateChannelKey(size: channelKeySize)
				channelKey = key
			}
			if !canEnablePreciseLocation {
				preciseLocation = false
			}
			hasChanges = true
		}
		.onChange(of: channelKey) {
			if !canEnablePreciseLocation {
				preciseLocation = false
			}
			hasChanges = true
		}
		.onChange(of: channelRole) {
			hasChanges = true
		}
		.onChange(of: preciseLocation) { _, loc in
			if loc == true {
				if !canEnablePreciseLocation {
					preciseLocation = false
				} else if requiresPrivacyAcknowledgement && !isApplyingConfirmedPreciseLocation {
					preciseLocation = false
					isPresentingUnencryptedLocationWarning = true
				} else {
					positionPrecision = 32
					isApplyingConfirmedPreciseLocation = false
				}
			} else {
				positionPrecision = 14
			}
			hasChanges = true
		}
		.onChange(of: positionPrecision) {
			hasChanges = true
		}
		.onChange(of: positionsEnabled) { _, pe in
			if pe {
				if positionPrecision == 0 {
					positionPrecision = 15
				}
			} else {
				positionPrecision = 0
			}
			hasChanges = true
		}
		.onChange(of: uplink) {
			hasChanges = true
		}
		.onChange(of: downlink) {
			hasChanges = true
		}
		.onFirstAppear {
			if isHamMode {
				channelKeySize = ChannelPreciseLocationPolicy.requiredChannelKeySize(
					currentKeySize: channelKeySize,
					isHamMode: isHamMode
				)
				channelKey = ""
			}
			let tempKey = Data(base64Encoded: channelKey) ?? Data()
			if tempKey.count == channelKeySize || channelKeySize == -1 {
				hasValidKey = true
			} else {
				hasValidKey = false
			}
		}
		.alert("Unencrypted Precise Location", isPresented: $isPresentingUnencryptedLocationWarning) {
			Button("Cancel", role: .cancel) {}
			Button("I Accept the Risk", role: .destructive) {
				isApplyingConfirmedPreciseLocation = true
				preciseLocation = true
			}
		} message: {
			Text(
				"By continuing, you authorize this node to transmit your precise location over an unencrypted mesh channel. " +
				"Anyone receiving or relaying these transmissions may view, collect, copy, retain, publish, or otherwise process this information. " +
				"Meshtastic cannot control third-party mesh participants, gateways, or storage systems. Proceed only if you accept these risks and are responsible for complying with applicable laws and amateur-radio regulations."
			)
		}
	}
}

enum ChannelPreciseLocationPolicy {
	static func canEnablePreciseLocation(channelKeySize: Int, channelRole: Int, isHamMode: Bool) -> Bool {
		guard channelRole > 0 else { return false }
		return isHamMode ? channelKeySize == 0 : channelKeySize > 1
	}

	static func requiresPrivacyAcknowledgement(channelKeySize: Int, isHamMode: Bool) -> Bool {
		channelKeySize == 0 && isHamMode
	}

	static func requiredChannelKeySize(currentKeySize: Int, isHamMode: Bool) -> Int {
		isHamMode ? 0 : currentKeySize
	}
}

#Preview {
	ChannelForm(
		channelIndex: .constant(0),
		channelName: .constant("LongFast"),
		channelKeySize: .constant(32),
		channelKey: .constant("AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="),
		channelRole: .constant(1),
		uplink: .constant(false),
		downlink: .constant(false),
		positionPrecision: .constant(14),
		preciseLocation: .constant(false),
		positionsEnabled: .constant(true),
		hasChanges: .constant(false),
		hasValidKey: .constant(true),
		supportedVersion: .constant(true),
		isHamMode: false
	)
}
