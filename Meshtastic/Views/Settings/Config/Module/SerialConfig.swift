//
//  SerialConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
import SwiftUI

struct SerialConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	
	@State var enabled = false
	@State var echo = false
	@State var rxd = 0
	@State var txd = 0
	@State var baudRate = 0
	@State var timeout = 0
	@State var mode = 0
	
	var body: some View {
		
		VStack {

			Form {
				
				Section(header: Text("options")) {
				
					Toggle(isOn: $enabled) {

						Label("enabled", systemImage: "terminal")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $echo) {

						Label("echo", systemImage: "repeat")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("If set, any packets you send will be echoed back to your device.")
						.font(.caption)
					
					Picker("Baud", selection: $baudRate ) {
						ForEach(SerialBaudRates.allCases) { sbr in
							Text(sbr.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Picker("timeout", selection: $timeout ) {
						ForEach(SerialTimeoutIntervals.allCases) { sti in
							Text(sti.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("The amount of time to wait before we consider your packet as done.")
						.font(.caption)
					
					Picker("mode", selection: $mode ) {
						ForEach(SerialModeTypes.allCases) { smt in
							Text(smt.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
				}
				Section(header: Text("GPIO")) {
					
					Picker("Receive data (rxd) GPIO pin", selection: $rxd) {
						ForEach(0..<40) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())

					Picker("Transmit data (txd) GPIO pin", selection: $txd) {
						ForEach(0..<40) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Set the GPIO pins for RXD and TXD.")
						.font(.caption)
				}
			}
			.disabled(node == nil)
			
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
				let nodeName = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : NSLocalizedString("unknown", comment: "Unknown")
				let buttonText = String.localizedStringWithFormat(NSLocalizedString("save.config %@", comment: "Save Config for %@"), nodeName)
				Button(buttonText) {
					var sc = ModuleConfig.SerialConfig()
					sc.enabled = enabled
					sc.echo = echo
					sc.rxd = UInt32(rxd)
					sc.txd = UInt32(txd)
					sc.baud = SerialBaudRates(rawValue: baudRate)!.protoEnumValue()
					sc.timeout = UInt32(timeout)
					sc.mode	= SerialModeTypes(rawValue: mode)!.protoEnumValue()
					
					let adminMessageId =  bleManager.saveSerialModuleConfig(config: sc, fromUser: node!.user!, toUser: node!.user!)
					
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
			message: {
				Text("config.save.confirm")
			}
			.navigationTitle("serial.config")
			.navigationBarItems(trailing:

				ZStack {
					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
			})
			.onAppear {
					
				self.bleManager.context = context
				self.enabled = node?.serialConfig?.enabled ?? false
				self.echo = node?.serialConfig?.echo ?? false
				self.rxd = Int(node?.serialConfig?.rxd ?? 0)
				self.txd = Int(node?.serialConfig?.txd ?? 0)
				self.baudRate = Int(node?.serialConfig?.baudRate ?? 0)
				self.timeout = Int(node?.serialConfig?.timeout ?? 0)
				self.mode = Int(node?.serialConfig?.mode ?? 0)
				self.hasChanges = false

			}
			.onChange(of: enabled) { newEnabled in
				
				if node != nil && node!.serialConfig != nil {
				
					if newEnabled != node!.serialConfig!.enabled { hasChanges = true	}
				}
			}
			.onChange(of: echo) { newEcho in
				
				if node != nil && node!.serialConfig != nil {
				
					if newEcho != node!.serialConfig!.echo { hasChanges = true	}
				}
			}
			.onChange(of: rxd) { newRxd in
				
				if node != nil && node!.serialConfig != nil {
				
					if newRxd != node!.serialConfig!.rxd { hasChanges = true	}
				}
			}
			.onChange(of: txd) { newTxd in
				
				if node != nil && node!.serialConfig != nil {

					if newTxd != node!.serialConfig!.txd { hasChanges = true	}
				}
			}
			.onChange(of: baudRate) { newBaud in
				
				if node != nil && node!.serialConfig != nil {
				
					if newBaud != node!.serialConfig!.baudRate { hasChanges = true	}
				}
			}
			.onChange(of: timeout) { newTimeout in
				
				if node != nil && node!.serialConfig != nil {
					
					if newTimeout != node!.serialConfig!.timeout { hasChanges = true	}
				}
			}
			.onChange(of: mode) { newMode in
				
				if node != nil && node!.serialConfig != nil {
					
					if newMode != node!.serialConfig!.mode { hasChanges = true	}
				}
			}
		}
	}
}
