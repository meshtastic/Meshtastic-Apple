import SwiftUI
@preconcurrency import SwiftData
import MeshtasticProtobufs
import OSLog

struct PowerConfig: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack

	let node: NodeInfoEntity?

	@State private var isPowerSaving = false

	@State private var shutdownOnPowerLoss = false
	@State private var shutdownAfterSecs: UpdateInterval = UpdateInterval(from: 0)
	@State private var adcOverride = false
	@State private var adcMultiplier: Float = 0.0

	@State private var waitBluetoothSecs = 60
	@State private var lsSecs = 300
	@State private var minWakeSecs = 10

	@State private var architecture: Architecture?
	
	@State private var hasChanges: Bool = false
	@FocusState private var isFocused: Bool

	var body: some View {
		Form {
			ConfigHeader(title: "Power Config", config: \.powerConfig, node: node, onAppear: setPowerValues)

			Section {
				if let architecture, (architecture == .esp32 || architecture == .esp32S3) || (architecture == .nrf52840 && (node?.deviceConfig?.role ?? 0 == 5 || node?.deviceConfig?.role ?? 0 == 6)) {
					Toggle(isOn: $isPowerSaving) {
						Label("Power Saving", systemImage: "bolt")
						Text("Will sleep everything as much as possible, for the tracker and sensor role this will also include the lora radio. Don't use this setting if you want to use your device with the phone apps or are using a device without a user button.")
					}
					.tint(.accentColor)
				}
				Toggle(isOn: $shutdownOnPowerLoss) {
					Label("Shutdown on Power Loss", systemImage: "power")
				}
				.tint(.accentColor)
				if shutdownOnPowerLoss {
					UpdateIntervalPicker(
						config: .all,
						pickerLabel: "After",
						selectedInterval: $shutdownAfterSecs
					)
				}
			} header: {
				Text("Power")
			}
			if let architecture, architecture == .esp32 || architecture == .esp32S3 {
				Section {
					Toggle(isOn: $adcOverride) {
						Text("ADC Override")
					}
					.tint(.accentColor)

					if adcOverride {
						HStack {
							Text("Multiplier")
							Spacer()
							FloatField(title: "Multiplier", number: $adcMultiplier) {
								$0 > 0.0
							}
							.focused($isFocused)
							Spacer()
						}
					}
				} header: {
					Text("Battery")
				}
			}
		}
		.disabled(!accessoryManager.isConnected || node?.powerConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				performConfigSave(
					node: node,
					context: context,
					accessoryManager: accessoryManager,
					hasChanges: $hasChanges,
					dismiss: goBack
				) { fromUser, toUser in
					var config = Config.PowerConfig()
					config.isPowerSaving = isPowerSaving
					config.onBatteryShutdownAfterSecs = shutdownOnPowerLoss ? UInt32(shutdownAfterSecs.intValue) : 0
					config.adcMultiplierOverride = adcOverride ? adcMultiplier : 0
					config.waitBluetoothSecs = UInt32(waitBluetoothSecs)
					config.lsSecs = UInt32(lsSecs)
					config.minWakeSecs = UInt32(minWakeSecs)
					_ = try await accessoryManager.savePowerConfig(
						config: config,
						fromUser: fromUser,
						toUser: toUser
					)
				}
			}
			}
		}
		.navigationTitle("Power Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
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
			if let hwModelId = node?.user?.hwModelId {
				let hwModelValue = Int64(hwModelId)
				let descriptor = FetchDescriptor<DeviceHardwareEntity>(
					predicate: #Predicate { $0.hwModel == hwModelValue }
				)
				if let hardware = try? context.fetch(descriptor),
				   let archString = HardwareCatalogResolver.presentation(for: hwModelValue, in: hardware)?.architecture,
				   let arch = Architecture(rawValue: archString) {
					architecture = arch
				}
			}
		}
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.powerConfig == nil },
				request: accessoryManager.requestPowerConfig
			)
		}
		.onChange(of: isPowerSaving) { oldIsPowerSaving, newIsPowerSaving in
			if oldIsPowerSaving != newIsPowerSaving && newIsPowerSaving != node?.powerConfig?.isPowerSaving { hasChanges = true }
		}
		.onChange(of: shutdownOnPowerLoss) { _, newShutdownOnPowerLoss in
			if newShutdownOnPowerLoss {
				hasChanges = true
			}
		}
		.onChange(of: shutdownAfterSecs.intValue) { oldShutdownAfterSecs, newShutdownAfterSecs in
			if oldShutdownAfterSecs != newShutdownAfterSecs && newShutdownAfterSecs != (node?.powerConfig?.minWakeSecs ?? -1) { hasChanges = true }
		}
		.onChange(of: adcOverride) {
			hasChanges = true
		}
		.onChange(of: adcMultiplier) { _, newAdcMultiplier in
			if  newAdcMultiplier != (node?.powerConfig?.adcMultiplierOverride ?? -1) { hasChanges = true }
		}
		.onChange(of: waitBluetoothSecs) { oldWaitBluetoothSecs, newWaitBluetoothSecs in
			if oldWaitBluetoothSecs != newWaitBluetoothSecs && newWaitBluetoothSecs != (node?.powerConfig?.waitBluetoothSecs ?? -1) { hasChanges = true }
		}
		.onChange(of: lsSecs) { _, newLsSecs in
			if newLsSecs != (node?.powerConfig?.lsSecs ?? -1) { hasChanges = true }
		}
		.onChange(of: minWakeSecs) { _, newMinWakeSecs in
			if newMinWakeSecs != (node?.powerConfig?.minWakeSecs ?? -1) { hasChanges = true }
		}
	}

	private func setPowerValues() {
		isPowerSaving = node?.powerConfig?.isPowerSaving ?? isPowerSaving

		shutdownAfterSecs = UpdateInterval(from: Int(node?.powerConfig?.onBatteryShutdownAfterSecs ?? Int32(shutdownAfterSecs.intValue)))
		shutdownOnPowerLoss = shutdownAfterSecs.intValue != 0

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

#Preview {
	PowerConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
