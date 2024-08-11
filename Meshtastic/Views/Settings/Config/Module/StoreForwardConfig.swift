//
//  StoreForward.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen  8/26/23.
//
import MeshtasticProtobufs
import OSLog
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
	/// Is a S&F Router
	@State var isRouter = false
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
				ConfigHeader(title: "storeforward", config: \.storeForwardConfig, node: node, onAppear: setStoreAndForwardValues)

				Section(header: Text("options")) {

					Toggle(isOn: $enabled) {
						Label("enabled", systemImage: "envelope.arrow.triangle.branch")
						Text("Enables the store and forward module. Store and forward must be enabled on both client and router devices.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)
					if enabled {
						HStack {
							Picker(selection: $isRouter, label: Text("Role")) {
								Text("Client")
									.tag(false)
								Text("Router")
									.tag(true)
							}
							.pickerStyle(SegmentedPickerStyle())
							.padding(.top, 5)
							.padding(.bottom, 5)
						}
						VStack {
							if isRouter {
								Text("Store and forward router devices must also be in the router or router client device role and requires a ESP32 device with PSRAM.")
									.foregroundColor(.gray)
									.font(.callout)
							} else {
								Text("Store and forward clients can request history from routers on the network.")
									.foregroundColor(.gray)
									.font(.callout)
							}
						}
					}
				}

				if isRouter {
					Section(header: Text("Router Options")) {
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
							Text("Two Hours").tag(7200)
						}
						.pickerStyle(DefaultPickerStyle())
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.disabled(self.bleManager.connectedPeripheral == nil || node?.storeForwardConfig == nil)
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
			if connectedNode != nil {
				/// Let the user set isRouter for the connected node, for nodes on the mesh set isRouter based
				/// on receipt of a primary heartbeat
				if connectedNode?.num ?? 0 == node?.num ?? -1 {
					connectedNode?.storeForwardConfig?.isRouter = isRouter
					do {
						try context.save()
					} catch {
						Logger.mesh.error("Failed to save isRouter: \(error.localizedDescription)")
					}
				}

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
				}
			}
		}
		.navigationTitle("storeforward.config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: bleManager.connectedPeripheral?.shortName ?? "?"
				)
			}
		)
		.onAppear {
			// Need to request a Detection Sensor Module Config from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.storeForwardConfig == nil {
				Logger.mesh.debug("empty store and forward module config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestStoreAndForwardModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: enabled) { newEnabled in
			if node != nil && node?.storeForwardConfig != nil {
				if newEnabled != node!.storeForwardConfig!.enabled { hasChanges = true }
			}
		}
		.onChange(of: isRouter) { newIsRouter in
			if node != nil && node?.storeForwardConfig != nil {
				if newIsRouter != node!.storeForwardConfig!.isRouter { hasChanges = true }
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
	func setStoreAndForwardValues() {
		self.enabled = (node?.storeForwardConfig?.enabled ?? false)
		self.isRouter = (node?.storeForwardConfig?.isRouter ?? false)
		self.heartbeat = (node?.storeForwardConfig?.heartbeat ?? true)
		self.records = Int(node?.storeForwardConfig?.records ?? 50)
		self.historyReturnMax = Int(node?.storeForwardConfig?.historyReturnMax ?? 100)
		self.historyReturnWindow = Int(node?.storeForwardConfig?.historyReturnWindow ?? 7200)
		self.hasChanges = false
	}
}
