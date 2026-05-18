//
//  BluetoothConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 8/18/22.
//

import MeshtasticProtobufs
import OSLog
import SwiftUI

struct BluetoothConfig: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	var node: NodeInfoEntity?
	@State var hasChanges = false
	@State var enabled = true
	@State var mode = 0
	@State var fixedPin = "123456"
	@State var shortPin = false
	var pinLength: Int = 6
	let numberFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .none
		return formatter
	}()
	var body: some View {
		Form {
			ConfigHeader(title: "Bluetooth", config: \.bluetoothConfig, node: node, onAppear: setBluetoothValues)
			
			Section(header: Text("Options")) {
				Toggle(isOn: $enabled) {
					Label("Enabled", systemImage: "antenna.radiowaves.left.and.right")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Picker("Pairing Mode", selection: $mode ) {
					ForEach(BluetoothModes.allCases) { bm in
						Text(bm.description)
					}
				}
				.pickerStyle(DefaultPickerStyle())
				if mode == 1 {
					HStack {
						Label("Fixed Pin", systemImage: "wallet.pass")
						TextField("Fixed Pin", text: $fixedPin)
							.foregroundColor(.gray)
							.onChange(of: fixedPin) {
								// Only allow numeric characters
								let filtered = fixedPin.filter(\.isNumber)
								// Strip leading zeros since the protobuf value is a UInt32
								let trimmed = String(filtered.drop(while: { $0 == "0" }))
								// Require that pin is no more than 6 numbers and no less than 6 numbers
								let clamped = String(trimmed.prefix(pinLength))
								if fixedPin != clamped {
									fixedPin = clamped
								}
								shortPin = clamped.count < pinLength
							}
							.foregroundColor(.gray)
					}
					.keyboardType(.decimalPad)
					if shortPin {
						Text("BLE Pin must be 6 digits long.")
							.font(.callout)
							.foregroundColor(.red)
					}
				}
			}
		}
		.disabled(!accessoryManager.isConnected || node?.bluetoothConfig == nil)
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
					var bc = Config.BluetoothConfig()
					bc.enabled = enabled
					bc.mode = BluetoothModes(rawValue: mode)?.protoEnumValue() ?? Config.BluetoothConfig.PairingMode.randomPin
					bc.fixedPin = UInt32(fixedPin) ?? 123456
					_ = try await accessoryManager.saveBluetoothConfig(config: bc, fromUser: fromUser, toUser: toUser)
				}
			}
			}
		}
		.navigationTitle("Bluetooth Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
				
			}
		)
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.bluetoothConfig == nil },
				request: accessoryManager.requestBluetoothConfig
			)
		}
		.onChange(of: enabled) { oldEnabled, newEnabled in
			if oldEnabled != newEnabled && newEnabled != node?.bluetoothConfig?.enabled { hasChanges = true }
		}
		.onChange(of: mode) { oldNode, newNode in
			if oldNode != newNode && newNode != node?.bluetoothConfig?.mode ?? -1 { hasChanges = true }
		}
		.onChange(of: fixedPin) { oldFixedPin, newFixedPin in
			if oldFixedPin != newFixedPin && newFixedPin != String(node?.bluetoothConfig?.fixedPin ?? -1) { hasChanges = true }
		}
	}
	func setBluetoothValues() {
		self.enabled = node?.bluetoothConfig?.enabled ?? true
		self.mode = Int(node?.bluetoothConfig?.mode ?? 0)
		self.fixedPin = String(node?.bluetoothConfig?.fixedPin ?? 123456)
		self.hasChanges = false
	}
}

#Preview {
	BluetoothConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
