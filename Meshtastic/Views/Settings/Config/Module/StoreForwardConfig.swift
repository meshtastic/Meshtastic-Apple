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
	/// Is a S&F Server
	@State var isServer = false
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
				ConfigHeader(title: "Store & Forward", config: \.storeForwardConfig, node: node, onAppear: setStoreAndForwardValues)

				Section(header: Text("Options")) {
					Toggle(isOn: $enabled) {
						Label("Enabled", systemImage: "envelope.arrow.triangle.branch")
						Text("Enables the store and forward module.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)
				}

				if enabled {
					Section(header: Text("Settings")) {
						Toggle(isOn: $heartbeat) {
							Label("Send Heartbeat", systemImage: "waveform.path.ecg")
							Text("Send a heartbeat to advertise the server's presence.")
						}
						Picker("Number of records", selection: $records) {
							Text("Unset").tag(0)
							Text("25").tag(25)
							Text("50").tag(50)
							Text("75").tag(75)
							Text("100").tag(100)
						}
						.pickerStyle(DefaultPickerStyle())
						Picker("History Return Max", selection: $historyReturnMax) {
							Text("Unset").tag(0)
							Text("25").tag(25)
							Text("50").tag(50)
							Text("75").tag(75)
							Text("100").tag(100)
						}
						.pickerStyle(DefaultPickerStyle())
						Picker("History Return Window", selection: $historyReturnWindow) {
							Text("Unset").tag(0)
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

					Section(header: Text("Server Option")) {
						Toggle(isOn: $isServer) {
							Label("Server", systemImage: "server.rack")
							Text("Enable this device as a Store and Forward server. Requires an ESP32 device with PSRAM.")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.listRowSeparator(.visible)
						if isServer {
							Text("Store and forward servers require an ESP32 device with PSRAM or Linux Native.")
								.foregroundColor(.gray)
								.font(.callout)
						}
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.disabled(self.bleManager.connectedPeripheral == nil || node?.storeForwardConfig == nil)
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
			if connectedNode != nil {
				/// Let the user set isServer for the connected node, for nodes on the mesh set isServer based
				/// on receipt of a primary heartbeat
				if connectedNode?.num ?? 0 == node?.num ?? -1 {
					connectedNode?.storeForwardConfig?.isRouter = isServer
					do {
						try context.save()
					} catch {
						Logger.mesh.error("Failed to save isServer: \(error.localizedDescription, privacy: .public)")
					}
				}

				var sfc = ModuleConfig.StoreForwardConfig()
				sfc.isServer = isServer
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
		.navigationTitle("Store & Forward Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: bleManager.connectedPeripheral?.shortName ?? "?"
				)
			}
		)
		.onFirstAppear {
			// Need to request a StoreForwardModuleConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.storeForwardConfig == nil {
								Logger.mesh.info("⚙️ Empty or expired store & forward module config requesting via PKI admin")
								_ = bleManager.requestStoreAndForwardModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin, empty store & forward module config")
							_ = bleManager.requestStoreAndForwardModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
						}
					}
				}
			}
		}
		.onChange(of: enabled) { oldEnabled, newEnabled in
			if oldEnabled != newEnabled && newEnabled != node!.storeForwardConfig!.enabled { hasChanges = true }
		}
		.onChange(of: isServer) { oldIsServer, newIsServer in
			if oldIsServer != newIsServer && newIsServer != node!.storeForwardConfig!.isRouter { hasChanges = true }
		}
		.onChange(of: heartbeat) { oldHeartbeat, newHeartbeat in
			if oldHeartbeat != newHeartbeat && newHeartbeat != node?.storeForwardConfig?.heartbeat ?? true { hasChanges = true }
		}
		.onChange(of: records) { oldRecords, newRecords in
			if oldRecords != newRecords && newRecords != node!.storeForwardConfig?.records ?? -1 { hasChanges = true }
		}
		.onChange(of: historyReturnMax) { oldHistoryReturnMax, newHistoryReturnMax in
			if oldHistoryReturnMax != newHistoryReturnMax && newHistoryReturnMax != node!.storeForwardConfig?.historyReturnMax ?? -1 { hasChanges = true }
		}
		.onChange(of: historyReturnWindow) { oldHistoryReturnWindow, newHistoryReturnWindow in
			if oldHistoryReturnWindow != newHistoryReturnWindow && newHistoryReturnWindow != node!.storeForwardConfig?.historyReturnWindow ?? -1 { hasChanges = true }
		}
	}

	func setStoreAndForwardValues() {
		self.enabled = (node?.storeForwardConfig?.enabled ?? false)
		self.isServer = (node?.storeForwardConfig?.isRouter ?? false)
		self.heartbeat = (node?.storeForwardConfig?.heartbeat ?? true)
		self.records = Int(node?.storeForwardConfig?.records ?? 50)
		self.historyReturnMax = Int(node?.storeForwardConfig?.historyReturnMax ?? 100)
		self.historyReturnWindow = Int(node?.storeForwardConfig?.historyReturnWindow ?? 7200)
		self.hasChanges = false
	}
}
