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
	@Environment(\.managedObjectContext) var context
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
								// Don't let the first character be 0 because it will get stripped when saving a UInt32
								if fixedPin.first == "0" {
									fixedPin = fixedPin.replacing("0", with: "")
								}
								// Require that pin is no more than 6 numbers and no less than 6 numbers
								if fixedPin.utf8.count == pinLength {
									shortPin = false
								} else if fixedPin.utf8.count > pinLength {
									shortPin = false
									fixedPin = String(fixedPin.prefix(pinLength))
								} else if fixedPin.utf8.count < pinLength {
									shortPin = true
								}
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

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			if let myNodeNum = accessoryManager.activeDeviceNum,
				let connectedNode = getNodeInfo(id: myNodeNum, context: context) {
				var bc = Config.BluetoothConfig()
				bc.enabled = enabled
				bc.mode = BluetoothModes(rawValue: mode)?.protoEnumValue() ?? Config.BluetoothConfig.PairingMode.randomPin
				bc.fixedPin = UInt32(fixedPin) ?? 123456
				Task {
					// TODO: ADMINIndex?
					_ = try await accessoryManager.saveBluetoothConfig(config: bc, fromUser: connectedNode.user!, toUser: node!.user!)
					Task { @MainActor in
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
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
			// Need to request a BluetoothConfig from the remote node before allowing changes
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				if let connectedNode = getNodeInfo(id: deviceNum, context: context) {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.bluetoothConfig == nil {
								Task {
									do {
										Logger.mesh.info("⚙️ Empty or expired bluetooth config requesting via PKI admin")
										// TODO: AdminIndex?
										try await accessoryManager.requestBluetoothConfig(fromUser: connectedNode.user!, toUser: node.user!)
									} catch {
										Logger.mesh.info("🚨 Bluetooth config request failed")
									}
								}

							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
						}
					}
				}
			}
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
