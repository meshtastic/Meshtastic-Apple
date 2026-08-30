//
//  User.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/27/22.
//
import SwiftData
import MeshtasticProtobufs
import SwiftUI

struct UserConfig: View {
	
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
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
	@State var callSign: String = ""
	@State var hamLongName: String = ""
	@State var isUnmessagable: Bool = false
	@State var isLicensed = false
	@State var overrideDutyCycle = false
	@State var overrideFrequency: Float = 0.0
	@State var txPower = 0
	@FocusState var focusedField: Field?
	
	public var minimumVersion = "2.6.9"
	let floatFormatter = frequencyOverrideFormatter
	
	var body: some View {
		
		Form {
			Section(header: Text("User Details")) {
				
				if isLicensed {
					VStack(alignment: .leading) {
						HStack {
							Label("Call Sign", systemImage: "person.crop.rectangle.fill")
							TextField("Call Sign", text: $callSign)
								.onChange(of: callSign) {
									callSign = HamName.limitCallSign(callSign.withoutVariationSelectors)
									longName = HamName(callSign: callSign, longName: hamLongName).composed
								}
						}
						Text("Call Sign can be up to 7 bytes long.")
							.foregroundColor(.gray)
							.font(.callout)
						if callSign.isEmpty {
							Label("Call Sign must not be empty", systemImage: "exclamationmark.square")
								.foregroundColor(.red)
						}
						HStack {
							Label("Long Name", systemImage: "text.alignleft")
							TextField("Long Name", text: $hamLongName)
								.onChange(of: hamLongName) {
									hamLongName = HamName.limitLongName(hamLongName.withoutVariationSelectors)
									longName = HamName(callSign: callSign, longName: hamLongName).composed
								}
						}
						Text("Optional descriptive name, up to 14 bytes long.")
							.foregroundColor(.gray)
							.font(.callout)
					}
					.keyboardType(.default)
					.disableAutocorrection(true)
				} else {
					VStack(alignment: .leading) {
						HStack {
							Label("Long Name", systemImage: "person.crop.rectangle.fill")
							TextField("Long Name", text: $longName)
								.onChange(of: longName) {
									var newValue = longName.withoutVariationSelectors
									while newValue.utf8.count > 36 {
										newValue = String(newValue.dropLast())
									}
									longName = newValue
									if longName.contains("📵") {
										isUnmessagable = true
									}
								}
						}
						Text("Long Name can be up to 36 bytes long.")
							.foregroundColor(.gray)
							.font(.callout)
					}
					.keyboardType(.default)
					.disableAutocorrection(true)
				}
				VStack(alignment: .leading) {
					HStack {
						Label("Short Name", systemImage: "circlebadge.fill")
						TextField("Short Name", text: $shortName)
							.foregroundColor(.gray)
							.onChange(of: shortName) {
								let newValue = shortName.withoutVariationSelectors
								let totalBytes = newValue.utf8.count
								// Only mess with the value if it is too big
								if totalBytes > 4 {
									// If too long, drop the last thing entered
									shortName = String(shortName.dropLast())
								} else if shortName != newValue {
									// If not too long, make sure the stripped
									// variant is placed back in text field if necessary
									shortName = newValue
								}
							}
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					.disableAutocorrection(true)
					Text("The last 4 of the device MAC address will be appended to the short name to set the device's BLE Name.  Short name can be up to 4 bytes long.")
						.foregroundColor(.gray)
						.font(.callout)
					let supportedVersion = accessoryManager.checkIsVersionSupported(forVersion: minimumVersion)
					Toggle(isOn: $isUnmessagable) {
						Label("Unmessagable", systemImage: "iphone.slash")
						Text("Used to identify unmonitored or infrastructure nodes so that messaging is not avaliable to nodes that will never respond.")
							.font(.caption2)
					}
					.toggleStyle(.switch)
					.disabled(!supportedVersion)
				}
				// Only manage ham mode for the locally connected node
				if node?.num ?? 0 > 0 && node?.num ?? 0 == accessoryManager.activeDeviceNum ?? 0 {
					Toggle(isOn: $isLicensed) {
						Label("Licensed Operator", systemImage: "person.text.rectangle")
					}
					.toggleStyle(.switch)
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
										Button("Dismiss") {
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
		.disabled(!accessoryManager.isConnected)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				if accessoryManager.isConnected && hasChanges {
					Button {
						isPresentingSaveConfirm = true
					} label: {
						Label("Save", systemImage: "square.and.arrow.down")
					}
					.padding(.bottom)
					.controlSize(.large)
					.buttonStyle(.borderedProminent)
					.buttonBorderShape(.capsule)
					.confirmationDialog(
						"Are you sure?",
						isPresented: $isPresentingSaveConfirm,
						titleVisibility: .visible
					) {
						Button("Save User Config to \(node?.user?.longName ?? "Unknown")?") {
							if isLicensed && !HamName.hasCallSign(callSign) {
								return
							}
							
							let connectedUser = getUser(id: accessoryManager.activeDeviceNum ?? -1, context: context)
							let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? -1, context: context)
							if node != nil && connectedNode != nil {
								
								if !isLicensed {
									var u = User()
									u.shortName = shortName
									u.longName = longName
									u.isUnmessagable = isUnmessagable
									
									Task {
										_ = try await accessoryManager.saveUser(config: u, fromUser: connectedUser, toUser: node!.user!)
										Task { @MainActor in
											hasChanges = false
											goBack()
										}
									}
								} else {
									var ham = HamParameters()
									ham.shortName = shortName
									// ham.isUnmessagable = isUnmessagable
									ham.callSign = callSign
									ham.longName = hamLongName
									ham.txPower = Int32(txPower)
									ham.frequency = overrideFrequency
									Task {
										_ = try await accessoryManager.saveLicensedUser(ham: ham, fromUser: connectedUser, toUser: node!.user!)
										Task { @MainActor in
											hasChanges = false
											goBack()
										}
									}
								}
							}
						}
					} message: {
						Text("After config values save the node will reboot.")
					}
				}
			}
		}
		.navigationTitle("User Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onAppear {
			self.shortName = node?.user?.shortName ?? ""
			self.longName = node?.user?.longName ?? ""
			let hamName = HamName(composed: longName)
			self.callSign = hamName.callSign
			self.hamLongName = hamName.longName
			self.isUnmessagable = node?.user?.unmessagable ?? false
			self.isLicensed = node?.user?.isLicensed ?? false
			self.txPower = Int(node?.loRaConfig?.txPower ?? 0)
			self.overrideFrequency = node?.loRaConfig?.overrideFrequency ?? 0.00
			self.hasChanges = false
		}
		.onChange(of: shortName) { oldShort, newShort in
			if oldShort != newShort && newShort != node?.user?.shortName ?? "Unknown" { hasChanges = true }
		}
		.onChange(of: longName) { oldLong, newLong in
			if oldLong != newLong && newLong != node?.user?.longName ?? "Unknown" { hasChanges = true }
		}
		.onChange(of: isUnmessagable) { oldIsUnmessagable, newIsUnmessagable in
			if oldIsUnmessagable != newIsUnmessagable && newIsUnmessagable != node?.user?.unmessagable ?? true { hasChanges = true }
		}
		.onChange(of: isLicensed) { _, newIsLicensed in
			if let user = node?.user {
				if newIsLicensed != user.isLicensed {
					hasChanges = true
					if newIsLicensed {
						longName = HamName.forOnboarding(longName)
					} else {
						longName = HamName.forUnlicensing(longName)
					}
					let hamName = HamName(composed: longName)
					callSign = hamName.callSign
					hamLongName = hamName.longName
				}
			}
		}
		.onChange(of: overrideFrequency) {
			if isLicensed { hasChanges = true }
		}
		.onChange(of: txPower) {
			if isLicensed { hasChanges = true }
		}
	}
}

#Preview {
	UserConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
