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
		
		VStack {

			Form {
				
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
							Label("Fixed PIN", systemImage: "wallet.pass")
							TextField("Fixed PIN", text: $fixedPin)
								.foregroundColor(.gray)
								.onChange(of: fixedPin, perform: { value in
									//Require that pin is no more than 6 numbers and no less than 6 numbers
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
							
							Text("BLE Pin must be 6 digits long.")
								.font(.callout)
								.foregroundColor(.red)
						}
					}
				}
			}
			.disabled(bleManager.connectedPeripheral == nil)
			
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
				"Are you sure you want to save?",
				isPresented: $isPresentingSaveConfirm,
				titleVisibility: .visible
			) {
				Button("Save Config for \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")") {
					var bc = Config.BluetoothConfig()
					bc.enabled = enabled
					bc.mode = BluetoothModes(rawValue: mode)?.protoEnumValue() ?? Config.BluetoothConfig.PairingMode.randomPin
					bc.fixedPin = UInt32(fixedPin) ?? 123456
					let adminMessageId =  bleManager.saveBluetoothConfig(config: bc, fromUser: node!.user!, toUser: node!.user!)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			} message: {
				Text("After bluetooth config saves the node will reboot.")
			}
		}
		.navigationTitle("bluetooth.config")
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			self.bleManager.context = context
			self.enabled = node?.bluetoothConfig?.enabled ?? true
			self.mode = Int(node?.bluetoothConfig?.mode ?? 0)
			self.fixedPin = String(node?.bluetoothConfig?.fixedPin ?? 123456)
			self.hasChanges = false
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
}
