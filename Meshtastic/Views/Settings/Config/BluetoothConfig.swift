//
//  BluetoothConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 8/18/22.
//

import SwiftUI

struct BluetoothConfig: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	var node: NodeInfoEntity?
	@State private var isPresentingSaveConfirm: Bool = false
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
			if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
				Text("There has been no response to a request for device metadata over the admin channel for this node.")
					.font(.callout)
					.foregroundColor(.orange)

			} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
				// Let users know what is going on if they are using remote admin and don't have the config yet
				if node?.bluetoothConfig == nil {
					Text("Bluetooth config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
						.font(.callout)
						.foregroundColor(.orange)
				} else {
					Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
						.font(.title3)
						.onAppear {
							setBluetoothValues()
						}
				}
			} else if node != nil && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? -1 {
				Text("Configuration for: \(node?.user?.longName ?? "Unknown")")
					.font(.title3)
			} else {
				Text("Please connect to a radio to configure settings.")
					.font(.callout)
					.foregroundColor(.orange)
			}
			Section(header: Text("options")) {
				Toggle(isOn: $enabled) {
					Label("enabled", systemImage: "antenna.radiowaves.left.and.right")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Picker("bluetooth.pairingmode", selection: $mode ) {
					ForEach(BluetoothModes.allCases) { bm in
						Text(bm.description)
					}
				}
				.pickerStyle(DefaultPickerStyle())
				if mode == 1 {
					HStack {
						Label("bluetooth.mode.fixedpin", systemImage: "wallet.pass")
						TextField("bluetooth.mode.fixedpin", text: $fixedPin)
							.foregroundColor(.gray)
							.onChange(of: fixedPin, perform: { _ in
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
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.decimalPad)
					if shortPin {
						Text("bluetooth.pin.validation")
							.font(.callout)
							.foregroundColor(.red)
					}
				}
			}
		}
		.disabled(self.bleManager.connectedPeripheral == nil || node?.bluetoothConfig == nil)
		Button {
			isPresentingSaveConfirm = true
		} label: {
			Label("save", systemImage: "square.and.arrow.down")
		}
		.disabled(bleManager.connectedPeripheral == nil || !hasChanges || shortPin)
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.padding()
		.confirmationDialog(
			"are.you.sure",
			isPresented: $isPresentingSaveConfirm,
			titleVisibility: .visible
		) {
			let nodeName = node?.user?.longName ?? "unknown".localized
			let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
			Button(buttonText) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if connectedNode != nil {
					var bc = Config.BluetoothConfig()
					bc.enabled = enabled
					bc.mode = BluetoothModes(rawValue: mode)?.protoEnumValue() ?? Config.BluetoothConfig.PairingMode.randomPin
					bc.fixedPin = UInt32(fixedPin) ?? 123456
					let adminMessageId =  bleManager.saveBluetoothConfig(config: bc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
		} message: {
			Text("config.save.confirm")
		}
		.navigationTitle("bluetooth.config")
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			setBluetoothValues()
			// Need to request a BluetoothConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.bluetoothConfig == nil {
				print("empty bluetooth config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestBluetoothConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: enabled) { newEnabled in
			if node != nil && node!.bluetoothConfig != nil {
				if newEnabled != node!.bluetoothConfig!.enabled { hasChanges = true }
			}
		}
		.onChange(of: mode) { newMode in
			if node != nil && node!.bluetoothConfig != nil {
				if newMode != node!.bluetoothConfig!.mode { hasChanges = true }
			}
		}
		.onChange(of: fixedPin) { newFixedPin in
			if node != nil && node!.bluetoothConfig != nil {
				if newFixedPin != String(node!.bluetoothConfig!.fixedPin) { hasChanges = true }
			}
		}
	}
	func setBluetoothValues() {
		self.enabled = node?.bluetoothConfig?.enabled ?? true
		self.mode = Int(node?.bluetoothConfig?.mode ?? 0)
		self.fixedPin = String(node?.bluetoothConfig?.fixedPin ?? 123456)
		self.hasChanges = false
	}
}
