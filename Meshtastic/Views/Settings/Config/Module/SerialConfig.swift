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
	@EnvironmentObject var accessoryManager: AccessoryManager
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

				Section(header: Text("Options")) {

					Toggle(isOn: $enabled) {
						Label("Enabled", systemImage: "terminal")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Toggle(isOn: $echo) {
						Label("Echo", systemImage: "repeat")
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
					Picker("Timeout", selection: $timeout ) {
						ForEach(SerialTimeoutIntervals.allCases) { sti in
							Text(sti.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.hidden)
					Text("The amount of time to wait before we consider your packet as done.")
						.foregroundColor(.gray)
						.font(.callout)

					Picker("Mode", selection: $mode ) {
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
								Text("Unset")
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
								Text("Unset")
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
			.disabled(!accessoryManager.isConnected || node?.serialConfig == nil)

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? -1, context: context)
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

					Task {
						_ = try await accessoryManager.saveSerialModuleConfig(config: sc, fromUser: connectedNode!.user!, toUser: node!.user!)

						Task { @MainActor in
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
							goBack()
						}
					}
				}
			}
			.navigationTitle("Serial Config")
			.navigationBarItems(
				trailing: ZStack {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?"
					)
				}
			)
			.onFirstAppear {
				// Need to request a SerialModuleConfig from the remote node before allowing changes
				if let deviceNum = accessoryManager.activeDeviceNum, let node {
					let connectedNode = getNodeInfo(id: deviceNum, context: context)
					if let connectedNode {
						if node.num != deviceNum {
							if UserDefaults.enableAdministration && node.num != deviceNum {
								/// 2.5 Administration with session passkey
								let expiration = node.sessionExpiration ?? Date()
								if expiration < Date() || node.serialConfig == nil {
									Task {
										do {
											Logger.mesh.info("⚙️ Empty or expired serial module config requesting via PKI admin")
											try await accessoryManager.requestSerialModuleConfig(fromUser: connectedNode.user!, toUser: node.user!)
										} catch {
											Logger.mesh.info("🚨 Request for serial module config failed")
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
				if oldEnabled != newEnabled && newEnabled != node?.serialConfig?.enabled ?? false { hasChanges = true }
			}
			.onChange(of: echo) { oldEcho, newEcho in
				if oldEcho != newEcho && newEcho != node?.serialConfig?.echo ?? false { hasChanges = true }
			}
			.onChange(of: rxd) { oldRxd, newRxd in
				if oldRxd != newRxd && newRxd != node?.serialConfig?.rxd ?? -1 { hasChanges = true }
			}
			.onChange(of: txd) { oldTxd, newTxd in
				if oldTxd != newTxd && newTxd != node?.serialConfig?.txd ?? -1 { hasChanges = true }
			}
			.onChange(of: baudRate) { oldBaud, newBaud in
				if oldBaud != newBaud && newBaud != node?.serialConfig?.baudRate ?? -1 { hasChanges = true }
			}
			.onChange(of: timeout) { oldTimeout, newTimeout in
				if oldTimeout != newTimeout && newTimeout != node?.serialConfig?.timeout ?? -1 { hasChanges = true }
			}
			.onChange(of: overrideConsoleSerialPort) { oldOverrideConsoleSerialPort, newOverrideConsoleSerialPort in
				if oldOverrideConsoleSerialPort != newOverrideConsoleSerialPort && newOverrideConsoleSerialPort != node?.serialConfig?.overrideConsoleSerialPort ?? false { hasChanges = true }
			}
			.onChange(of: mode) { oldMode, newMode in
				if oldMode != newMode && newMode != node?.serialConfig?.mode ?? -1 { hasChanges = true }
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
