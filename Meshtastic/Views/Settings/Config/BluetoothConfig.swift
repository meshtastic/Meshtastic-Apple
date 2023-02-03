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
							.onChange(of: fixedPin, perform: { value in
								// Don't let the first character be 0 because it will get stripped when saving a UInt32
								if fixedPin.first == "0" {
									fixedPin = fixedPin.replacing("0", with: "")
								}
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
			let nodeName = node?.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown")
			let buttonText = String.localizedStringWithFormat(NSLocalizedString("save.config %@", comment: "Save Config for %@"), nodeName)
			Button(buttonText) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				var bc = Config.BluetoothConfig()
				bc.enabled = enabled
				bc.mode = BluetoothModes(rawValue: mode)?.protoEnumValue() ?? Config.BluetoothConfig.PairingMode.randomPin
				bc.fixedPin = UInt32(fixedPin) ?? 123456
				let adminMessageId =  bleManager.saveBluetoothConfig(config: bc, fromUser: connectedNode.user!, toUser: node!.user!, adminIndex: node?.myInfo?.adminIndex ?? 0)
				if adminMessageId > 0 {
					// Should show a saved successfully alert once I know that to be true
					// for now just disable the button after a successful save
					hasChanges = false
					goBack()
				}
			}
		} message: {
			Text("config.save.confirm")
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
			
			// Need to request a BluetoothConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.loRaConfig == nil {
				print("empty bluetooth config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if connectedNode.id > 0 {
					_ = bleManager.requestBluetoothConfig(fromUser: connectedNode.user!, toUser: node!.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
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
}
