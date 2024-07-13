//
//  SerialConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
import MeshtasticProtobufs
import OSLog
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
	@State var overrideConsoleSerialPort = false
	@State var mode = 0

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Serial", config: \.serialConfig, node: node, onAppear: setSerialValues)

				Section(header: Text("options")) {

					Toggle(isOn: $enabled) {
						Label("enabled", systemImage: "terminal")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Toggle(isOn: $echo) {
						Label("echo", systemImage: "repeat")
						Text("If set, any packets you send will be echoed back to your device.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Picker("Baud", selection: $baudRate ) {
						ForEach(SerialBaudRates.allCases) { sbr in
							Text(sbr.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(/*@START_MENU_TOKEN@*/.visible/*@END_MENU_TOKEN@*/)
					Picker("timeout", selection: $timeout ) {
						ForEach(SerialTimeoutIntervals.allCases) { sti in
							Text(sti.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.hidden)
					Text("The amount of time to wait before we consider your packet as done.")
						.foregroundColor(.gray)
						.font(.callout)

					Picker("mode", selection: $mode ) {
						ForEach(SerialModeTypes.allCases) { smt in
							Text(smt.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
				}
				Section(header: Text("GPIO")) {

					Picker("Receive data (rxd) GPIO pin", selection: $rxd) {
						ForEach(0..<49) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.visible)

					Picker("Transmit data (txd) GPIO pin", selection: $txd) {
						ForEach(0..<49) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.hidden)
					Text("Set the GPIO pins for RXD and TXD.")
						.foregroundColor(.gray)
						.font(.callout)
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.serialConfig == nil)

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if connectedNode != nil {
					var sc = ModuleConfig.SerialConfig()
					sc.enabled = enabled
					sc.echo = echo
					sc.rxd = UInt32(rxd)
					sc.txd = UInt32(txd)
					sc.baud = SerialBaudRates(rawValue: baudRate)!.protoEnumValue()
					sc.timeout = UInt32(timeout)
					sc.overrideConsoleSerialPort = overrideConsoleSerialPort
					sc.mode	= SerialModeTypes(rawValue: mode)!.protoEnumValue()

					let adminMessageId =  bleManager.saveSerialModuleConfig(config: sc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)

					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
			.navigationTitle("serial.config")
			.navigationBarItems(
				trailing: ConnectedDevice(ble: bleManager)
			)
			.onAppear {
				if self.bleManager.context == nil {
					self.bleManager.context = context
				}
				setSerialValues()
				// Need to request a SerialModuleConfig from the remote node before allowing changes
				if bleManager.connectedPeripheral != nil && node?.serialConfig == nil {
					Logger.mesh.debug("empty serial module config")
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if node != nil && connectedNode != nil {
						_ = bleManager.requestSerialModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					}
				}

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
			.onChange(of: overrideConsoleSerialPort) { newOverrideConsoleSerialPort in

				if node != nil && node!.serialConfig != nil {

					if newOverrideConsoleSerialPort != node!.serialConfig!.overrideConsoleSerialPort { hasChanges = true	}
				}
			}
			.onChange(of: mode) { newMode in

				if node != nil && node!.serialConfig != nil {

					if newMode != node!.serialConfig!.mode { hasChanges = true	}
				}
			}
		}
	}
	func setSerialValues() {
		self.enabled = node?.serialConfig?.enabled ?? false
		self.echo = node?.serialConfig?.echo ?? false
		self.rxd = Int(node?.serialConfig?.rxd ?? 0)
		self.txd = Int(node?.serialConfig?.txd ?? 0)
		self.baudRate = Int(node?.serialConfig?.baudRate ?? 0)
		self.timeout = Int(node?.serialConfig?.timeout ?? 0)
		self.mode = Int(node?.serialConfig?.mode ?? 0)
		self.overrideConsoleSerialPort = false // node?.serialConfig?.overrideConsoleSerialPort ?? false
		self.hasChanges = false
	}
}
