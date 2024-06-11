//
//  User.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/27/22.
//
import CoreData
import MeshtasticProtobufs
import SwiftUI

struct UserConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	enum Field: Hashable {
		case frequencyOverride
	}

	@State private var isPresentingFactoryResetConfirm: Bool = false
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var shortName = ""
	@State var longName: String = ""
	@State var isLicensed = false
	@State var overrideDutyCycle = false
	@State var overrideFrequency: Float = 0.0
	@State var txPower = 0

	@FocusState var focusedField: Field?

	let floatFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		return formatter
	}()

	var body: some View {

		VStack {
			Form {
				Section(header: Text("user.details")) {

					VStack(alignment: .leading) {
						HStack {
								   Label(isLicensed ? "call_sign".localized : "long_name".localized, systemImage: "person.crop.rectangle.fill")

								   TextField("long_name_placeholder".localized, text: $longName)
									   .onChange(of: longName) { _ in
										   let maxBytes = isLicensed ? 8 : 36
										   while longName.utf8.count > maxBytes {
											   longName.removeLast()
										   }
									   }
							   }
						.keyboardType(.default)
						.disableAutocorrection(true)
						if longName.isEmpty && isLicensed {
							Label("Call Sign must not be empty", systemImage: "exclamationmark.square")
								.foregroundColor(.red)
						}
						let label = isLicensed ? "call_sign".localized : "long_name".localized
						let maxBytes = isLicensed ? 8 : 36
						let message = String(format: "info_message".localized, label, maxBytes)

						Text(message)
							.foregroundColor(.gray)
							.font(.callout)

					}
					VStack(alignment: .leading) {
						HStack {
							Label("short_name_label".localized, systemImage: "circlebadge.fill")
							TextField("short_name_placeholder".localized, text: $shortName)
								.foregroundColor(.gray)
								.onChange(of: shortName) { _ in
									// Ensure the 'shortName' stays within 4 bytes to meet backend or protocol requirements
									while shortName.utf8.count > 4 {
										shortName.removeLast() // Correct method to remove the last character
									}
								}
								.foregroundColor(.gray) // This might be redundant
						}						.keyboardType(.default)
						.disableAutocorrection(true)
						Text("device_mac_info".localized)
							.foregroundColor(.gray)
							.font(.callout)
					}
					// Only manage ham mode for the locally connected node
					if node?.num ?? 0 > 0 && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? 0 {
						Toggle(isOn: $isLicensed) {
							Label("Licensed Operator", systemImage: "person.text.rectangle")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						if isLicensed {

							Text("Onboarding for licensed operators requires firmware 2.0.20 or greater. Make sure to refer to your local regulations and contact the local amateur frequency coordinators with questions.")
								.font(.caption2)
							Text("What licensed operator mode does:\n* Sets the node name to your call sign \n* Broadcasts node info every 10 minutes \n* Overrides frequency, dutycycle and tx power \n* Disables encryption")
								.font(.caption2)

							HStack {
								Label("Frequency", systemImage: "waveform.path.ecg")
								Spacer()
								TextField("Frequency Override", value: $overrideFrequency, formatter: floatFormatter)
									.toolbar {
										ToolbarItemGroup(placement: .keyboard) {
											Button("dismiss.keyboard") {
												focusedField = nil
											}
											.font(.subheadline)
										}
									}
									.keyboardType(.decimalPad)
									.scrollDismissesKeyboard(.immediately)
									.focused($focusedField, equals: .frequencyOverride)
							}
							HStack {
								Image(systemName: "antenna.radiowaves.left.and.right")
									.foregroundColor(.accentColor)
								Stepper("\(txPower)db Transmit Power", value: $txPower, in: 1...30, step: 1)
									.padding(5)
							}
						}
					}
				}
			}
			.disabled(bleManager.connectedPeripheral == nil)
			HStack {
				Button {
					isPresentingSaveConfirm = true
				} label: {
					Label("save", systemImage: "square.and.arrow.down")
				}
				.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.confirmationDialog(
					"are.you.sure",
					isPresented: $isPresentingSaveConfirm,
					titleVisibility: .visible
				) {
					Button("Save User Config to \(node?.user?.longName ?? "Unknown")?") {
						if longName.isEmpty && isLicensed {
							return
						}

						let connectedUser = getUser(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
						let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
						if node != nil && connectedNode != nil {

							if !isLicensed {
								var u = User()
								u.shortName = shortName
								u.longName = longName
								let adminMessageId = bleManager.saveUser(config: u, fromUser: connectedUser, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
								if adminMessageId > 0 {
									hasChanges = false
									goBack()
								}
							} else {
								var ham = HamParameters()
								ham.shortName = shortName
								ham.callSign = longName
								ham.txPower = Int32(txPower)
								ham.frequency = overrideFrequency
								let adminMessageId = bleManager.saveLicensedUser(ham: ham, fromUser: connectedUser, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
								if adminMessageId > 0 {
									hasChanges = false
									goBack()
								}
							}
						}
					}
				} message: {
					Text("config.save.confirm")
				}
			}
			Spacer()
		}
		.navigationTitle("user.config")
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			self.shortName = node?.user?.shortName ?? ""
			self.longName = node?.user?.longName ?? ""
			self.isLicensed = node?.user?.isLicensed ?? false
			self.txPower = Int(node?.loRaConfig?.txPower ?? 0)
			self.overrideFrequency = node?.loRaConfig?.overrideFrequency ?? 0.00
			self.hasChanges = false
		}
		.onChange(of: shortName) { newShort in
			if node != nil && node!.user != nil {
				if newShort != node?.user!.shortName { hasChanges = true }
			}
		}
		.onChange(of: longName) { newLong in
			if node != nil && node!.user != nil {
				if newLong != node?.user!.longName { hasChanges = true }
			}
		}
		.onChange(of: isLicensed) { newIsLicensed in
			if node != nil && node!.user != nil {
				if newIsLicensed != node?.user!.isLicensed {
					hasChanges = true
					if newIsLicensed {
						if node?.user?.longName?.count ?? 0 > 8 {
							longName = ""
						}
					}
				}
			}
		}
		.onChange(of: overrideFrequency) { _ in
			 hasChanges = true
		}
		.onChange(of: txPower) { _ in
			hasChanges = true
		}
	}
}
