import SwiftUI
import MeshtasticProtobufs
import OSLog

struct PowerConfig: View {
	@Environment(\.managedObjectContext) private var context
	@EnvironmentObject private var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	let node: NodeInfoEntity?

	@State private var isPowerSaving = false

	@State private var shutdownOnPowerLoss = false
	@State private var shutdownAfterSecs = 0
	@State private var adcOverride = false
	@State private var adcMultiplier: Float = 0.0

	@State private var waitBluetoothSecs = 60
	@State private var lsSecs = 300
	@State private var minWakeSecs = 10

	@State private var currentDevice: DeviceHardware?

	@State private var hasChanges: Bool = false
	@FocusState private var isFocused: Bool

	var body: some View {
		Form {
			ConfigHeader(title: "Power Config", config: \.powerConfig, node: node, onAppear: setPowerValues)

			Section {
				if (currentDevice?.architecture == .esp32 || currentDevice?.architecture == .esp32S3) || (currentDevice?.architecture == .nrf52840 && (node?.deviceConfig?.role ?? 0 == 5 || node?.deviceConfig?.role ?? 0 == 6)) {
					Toggle(isOn: $isPowerSaving) {
						Label("Power Saving", systemImage: "bolt")
						Text("Will sleep everything as much as possible, for the tracker and sensor role this will also include the lora radio. Don't use this setting if you want to use your device with the phone apps or are using a device without a user button.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
				Toggle(isOn: $shutdownOnPowerLoss) {
					Label("Shutdown on Power Loss", systemImage: "power")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				if shutdownOnPowerLoss {
					Picker("After", selection: $shutdownAfterSecs) {
						ForEach(PowerIntervals.allCases) { at in
							Text(at.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
				}
			} header: {
				Text("Power")
			}
			if currentDevice?.architecture == .esp32 || currentDevice?.architecture == .esp32S3 {
				Section {
					Toggle(isOn: $adcOverride) {
						Text("ADC Override")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					if adcOverride {
						HStack {
							Text("Multiplier")
							Spacer()
							FloatField(title: "Multiplier", number: $adcMultiplier) {
								(2.0 ... 6.0).contains($0)
							}
							.focused($isFocused)
							Spacer()
						}
					}
				} header: {
					Text("Battery")
				}
//				Section {
//					Picker("config.power.wait.bluetooth.secs", selection: $waitBluetoothSecs) {
//						ForEach(PowerIntervals.allCases) {
//							Text($0.description)
//						}
//					}
//					.pickerStyle(DefaultPickerStyle())
//					
//					Picker("config.power.ls.secs", selection: $lsSecs) {
//						ForEach(PowerIntervals.allCases) {
//							Text($0.description)
//						}
//					}
//					.pickerStyle(DefaultPickerStyle())
//					
//					Picker("config.power.min.wake.secs", selection: $minWakeSecs) {
//						ForEach(PowerIntervals.allCases) {
//							Text($0.description)
//						}
//					}
//					.pickerStyle(DefaultPickerStyle())
//					
//				} header: {
//					Text("config.power.section.sleep")
//				}
			}
		}
		.disabled(self.bleManager.connectedPeripheral == nil || node?.powerConfig == nil)
		.navigationTitle("Power Config")
		.navigationBarItems(trailing: ZStack {
			ConnectedDevice(
				bluetoothOn: bleManager.isSwitchedOn,
				deviceConnected: bleManager.connectedPeripheral != nil,
				name: "\(bleManager.connectedPeripheral?.shortName ?? "?")"
			)
		})
		.toolbar {
			ToolbarItemGroup(placement: .keyboard) {
				Spacer()
				Button("Dismiss") {
					isFocused = false
				}
				.font(.subheadline)
			}
		}
		.onFirstAppear {
			Api().loadDeviceHardwareData { (hw) in
				for device in hw {
					let currentHardware = node?.user?.hwModel ?? "UNSET"
					let deviceString = device.hwModelSlug.replacingOccurrences(of: "_", with: "")
					if deviceString == currentHardware {
						currentDevice = device
					}
				}
			}
			// Need to request a NetworkConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {

				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.powerConfig == nil {
								Logger.mesh.info("⚙️ Empty or expired power config requesting via PKI admin")
								_ = bleManager.requestPowerConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin, empty power config")
							_ = bleManager.requestPowerConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
						}
					}
				}
			}
		}
		.onChange(of: isPowerSaving) { oldIsPowerSaving, newIsPowerSaving in
			if oldIsPowerSaving != newIsPowerSaving && newIsPowerSaving != node?.powerConfig?.isPowerSaving { hasChanges = true }
		}
		.onChange(of: shutdownOnPowerLoss) { _, newShutdownOnPowerLoss in
			if newShutdownOnPowerLoss {
				hasChanges = true
			}
		}
		.onChange(of: shutdownAfterSecs) { oldShutdownAfterSecs, newShutdownAfterSecs in
			if oldShutdownAfterSecs != newShutdownAfterSecs && newShutdownAfterSecs != node?.powerConfig?.minWakeSecs ?? -1 { hasChanges = true }
		}
		.onChange(of: adcOverride) {
			hasChanges = true
		}
		.onChange(of: adcMultiplier) { _, newAdcMultiplier in
			if  newAdcMultiplier != node?.powerConfig?.adcMultiplierOverride ?? -1 { hasChanges = true }
		}
		.onChange(of: waitBluetoothSecs) { oldWaitBluetoothSecs, newWaitBluetoothSecs in
			if oldWaitBluetoothSecs != newWaitBluetoothSecs && newWaitBluetoothSecs != node?.powerConfig?.waitBluetoothSecs ?? -1 { hasChanges = true }
		}
		.onChange(of: lsSecs) { _, newLsSecs in
			if newLsSecs != node?.powerConfig?.lsSecs ?? -1 { hasChanges = true }
		}
		.onChange(of: minWakeSecs) { _, newMinWakeSecs in
			if newMinWakeSecs != node?.powerConfig?.minWakeSecs ?? -1 { hasChanges = true }
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			guard let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context),
				  let fromUser = connectedNode.user,
				  let toUser = node?.user else {
				return
			}

			var config = Config.PowerConfig()
			config.isPowerSaving = isPowerSaving
			config.onBatteryShutdownAfterSecs = shutdownOnPowerLoss ? UInt32(shutdownAfterSecs) : 0
			config.adcMultiplierOverride = adcOverride ? adcMultiplier : 0
			config.waitBluetoothSecs = UInt32(waitBluetoothSecs)
			config.lsSecs = UInt32(lsSecs)
			config.minWakeSecs = UInt32(minWakeSecs)

			let adminMessageId = bleManager.savePowerConfig(
				config: config,
				fromUser: fromUser,
				toUser: toUser,
				adminIndex: connectedNode.myInfo?.adminIndex ?? 0
			)
			if adminMessageId > 0 {
				// Should show a saved successfully alert once I know that to be true
				// for now just disable the button after a successful save
				hasChanges = false
				goBack()
			}
		}
	}

	private func setPowerValues() {
		isPowerSaving = node?.powerConfig?.isPowerSaving ?? isPowerSaving

		shutdownAfterSecs = Int(node?.powerConfig?.onBatteryShutdownAfterSecs ?? Int32(shutdownAfterSecs))
		shutdownOnPowerLoss = shutdownAfterSecs != 0

		adcMultiplier = node?.powerConfig?.adcMultiplierOverride ?? adcMultiplier
		adcOverride = adcMultiplier != 0

		waitBluetoothSecs = Int(node?.powerConfig?.waitBluetoothSecs ?? Int32(waitBluetoothSecs))
		lsSecs = Int(node?.powerConfig?.lsSecs ?? Int32(lsSecs))
		minWakeSecs = Int(node?.powerConfig?.minWakeSecs ?? Int32(minWakeSecs))
	}
}

/// Helper view for isolating user float input that can be validated before being applied.
private struct FloatField: View {
	let title: String
	@Binding var number: Float
	var isValid: (Float) -> Bool = { _ in true }

	@State private var typingNumber: Float = 0.0

	var body: some View {
		TextField(title.localized, value: $typingNumber, format: .number)
			.foregroundColor(.gray)
			.multilineTextAlignment(.trailing)
			.onChange(of: typingNumber) {
				if isValid(typingNumber) {
					number = typingNumber
				} else {
					typingNumber = number
				}
			}
			.keyboardType(.decimalPad)
			.onAppear {
				typingNumber = number
			}
	}
}
