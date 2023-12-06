//
//  StoreForward.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen  8/26/23.
//

import SwiftUI

struct StoreForwardConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	var node: NodeInfoEntity?
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges: Bool = false
	/// Enable the Store and Forward Module
	@State var enabled = false
	/// Send a Heartbeat
	@State var heartbeat: Bool = false
	/// Number of Records
	@State var records = 0
	/// Max number of history items to return
	@State var historyReturnMax = 0
	/// Time window for history
	@State var historyReturnWindow = 0

	var body: some View {
		VStack {
			Form {
				if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					Text("There has been no response to a request for device metadata over the admin channel for this node.")
						.font(.callout)
						.foregroundColor(.orange)
					
				} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					// Let users know what is going on if they are using remote admin and don't have the config yet
					if node?.storeForwardConfig == nil {
						Text("Store and forward config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
							.font(.callout)
							.foregroundColor(.orange)
					} else {
						Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
							.font(.title3)
							.onAppear {
								setDetectionSensorValues()
							}
					}
				} else if node != nil && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? 0 {
					Text("Configuration for: \(node?.user?.longName ?? "Unknown")")
						.font(.title3)
				} else {
					Text("Please connect to a radio to configure settings.")
						.font(.callout)
						.foregroundColor(.orange)
				}
				Section(header: Text("options")) {
					Toggle(isOn: $enabled) {
						Label("enabled", systemImage: "envelope.arrow.triangle.branch")
					}
					Toggle(isOn: $heartbeat) {
						Label("storeforward.heartbeat", systemImage: "waveform.path.ecg")
					}
					Picker("Number of records", selection: $records) {
						Text("unset").tag(0)
						Text("25").tag(25)
						Text("50").tag(50)
						Text("75").tag(75)
						Text("100").tag(100)
					}
					.pickerStyle(DefaultPickerStyle())
					Picker("History Return Max", selection: $historyReturnMax ) {
						Text("unset").tag(0)
						Text("25").tag(25)
						Text("50").tag(50)
						Text("75").tag(75)
						Text("100").tag(100)
					}
					.pickerStyle(DefaultPickerStyle())
					Picker("History Return Window", selection: $historyReturnWindow ) {
						Text("unset").tag(0)
						Text("One Minute").tag(60)
						Text("Five Minutes").tag(300)
						Text("Ten Minutes").tag(600)
						Text("Fifteen Minutes").tag(900)
						Text("Thirty Minutes").tag(1800)
						Text("One Hour").tag(3600)
					}
					.pickerStyle(DefaultPickerStyle())
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.disabled(self.bleManager.connectedPeripheral == nil || node?.storeForwardConfig == nil)
		}
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
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
			if connectedNode != nil {
				let nodeName = node?.user?.longName ?? "unknown".localized
				let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
				Button(buttonText) {
					var sfc = ModuleConfig.StoreForwardConfig()
					sfc.enabled = self.enabled
					sfc.heartbeat = self.heartbeat
					sfc.records = UInt32(self.records)
					sfc.historyReturnMax = UInt32(self.historyReturnMax)
					sfc.historyReturnWindow = UInt32(self.historyReturnWindow)
					let adminMessageId = bleManager.saveStoreForwardModuleConfig(config: sfc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}				}
			}
		}
		message: {
			Text("config.save.confirm")
		}
		.navigationTitle("storeforward.config")
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			self.bleManager.context = context
			setDetectionSensorValues()

			// Need to request a Detection Sensor Module Config from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.detectionSensorConfig == nil {
				print("empty store and forward module config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestDetectionSensorModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: enabled) { newEnabled in
			if node != nil && node?.detectionSensorConfig != nil {
				if newEnabled != node!.detectionSensorConfig!.enabled { hasChanges = true }
			}
		}
		.onChange(of: heartbeat) { newHeartbeat in
			if node != nil && node?.storeForwardConfig != nil {
				if newHeartbeat != node!.storeForwardConfig!.heartbeat { hasChanges = true }
			}
		}
		.onChange(of: records) { newRecords in
			if node != nil && node?.storeForwardConfig != nil {
				if newRecords != node!.storeForwardConfig!.records { hasChanges = true }
			}
		}
		.onChange(of: historyReturnMax) { newHistoryReturnMax in
			if node != nil && node?.storeForwardConfig != nil {
				if newHistoryReturnMax != node!.storeForwardConfig!.historyReturnMax { hasChanges = true }
			}
		}
		.onChange(of: historyReturnWindow) { newHistoryReturnWindow in
			if node != nil && node?.storeForwardConfig != nil {
				if newHistoryReturnWindow != node!.storeForwardConfig!.historyReturnWindow { hasChanges = true }
			}
		}
	}
	func setDetectionSensorValues() {
		self.enabled = (node?.storeForwardConfig?.enabled ?? false)
		self.heartbeat = (node?.storeForwardConfig?.heartbeat ?? true)
		self.records = Int(node?.storeForwardConfig?.records ?? 50)
		self.historyReturnMax = Int(node?.storeForwardConfig?.historyReturnMax ?? 100)
		self.historyReturnWindow = Int(node?.storeForwardConfig?.historyReturnWindow ?? 300)
		self.hasChanges = false
	}
}
