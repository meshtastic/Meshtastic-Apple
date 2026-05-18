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
	
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	let node: NodeInfoEntity?
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
		Form {
			ConfigHeader(title: "Store & Forward", config: \.storeForwardConfig, node: node, onAppear: setStoreAndForwardValues)
			
			Section(header: Text("Options")) {
				Toggle(isOn: $enabled) {
					Label("Enabled", systemImage: "envelope.arrow.triangle.branch")
					Text("Enables the store and forward module.")
				}
				.tint(.accentColor)
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
					Picker("History Return Max", selection: $historyReturnMax) {
						Text("Unset").tag(0)
						Text("25").tag(25)
						Text("50").tag(50)
						Text("75").tag(75)
						Text("100").tag(100)
					}
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
				}
				
				Section(header: Text("Server Option")) {
					Toggle(isOn: $isServer) {
						Label("Server", systemImage: "server.rack")
						Text("Enable this device as a Store and Forward server. Requires an ESP32 device with PSRAM.")
					}
					.tint(.accentColor)
					if isServer {
						Text("Store and forward servers require an ESP32 device with PSRAM or Linux Native.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}
			}
		}
		.scrollDismissesKeyboard(.interactively)
		.disabled(!accessoryManager.isConnected || node?.storeForwardConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				// Let the user set isServer for the connected node
				if let deviceNum = accessoryManager.activeDeviceNum,
				   let connectedNode = getNodeInfo(id: deviceNum, context: context),
				   connectedNode.num == node?.num ?? -1 {
					connectedNode.storeForwardConfig?.isRouter = isServer
					do {
						try context.save()
					} catch {
						Logger.mesh.error("Failed to save isServer: \(error.localizedDescription, privacy: .public)")
					}
				}
				performConfigSave(
					node: node,
					context: context,
					accessoryManager: accessoryManager,
					hasChanges: $hasChanges,
					dismiss: goBack
				) { fromUser, toUser in
					var sfc = ModuleConfig.StoreForwardConfig()
					sfc.isServer = isServer
					sfc.enabled = self.enabled
					sfc.heartbeat = self.heartbeat
					sfc.records = UInt32(self.records)
					sfc.historyReturnMax = UInt32(self.historyReturnMax)
					sfc.historyReturnWindow = UInt32(self.historyReturnWindow)
					_ = try await accessoryManager.saveStoreForwardModuleConfig(config: sfc, fromUser: fromUser, toUser: toUser)
				}
			}
			}
		}
		.navigationTitle("Store & Forward Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.storeForwardConfig == nil },
				request: accessoryManager.requestStoreAndForwardModuleConfig
			)
		}
		.onChange(of: enabled) { oldEnabled, newEnabled in
			if oldEnabled != newEnabled && newEnabled != node?.storeForwardConfig?.enabled { hasChanges = true }

			// Note: even if this is the connected node, we don't have to update AccessoryManager.wantStoreAndForwardPackets here, because the node will reboot after we save config changes, and we'll pick up the new value after we reconnect.
		}
		.onChange(of: isServer) { oldIsServer, newIsServer in
			if oldIsServer != newIsServer && newIsServer != node?.storeForwardConfig?.isRouter { hasChanges = true }
		}
		.onChange(of: heartbeat) { oldHeartbeat, newHeartbeat in
			if oldHeartbeat != newHeartbeat && newHeartbeat != node?.storeForwardConfig?.heartbeat ?? true { hasChanges = true }
		}
		.onChange(of: records) { oldRecords, newRecords in
			if oldRecords != newRecords && newRecords != node?.storeForwardConfig?.records ?? -1 { hasChanges = true }
		}
		.onChange(of: historyReturnMax) { oldHistoryReturnMax, newHistoryReturnMax in
			if oldHistoryReturnMax != newHistoryReturnMax && newHistoryReturnMax != node?.storeForwardConfig?.historyReturnMax ?? -1 { hasChanges = true }
		}
		.onChange(of: historyReturnWindow) { oldHistoryReturnWindow, newHistoryReturnWindow in
			if oldHistoryReturnWindow != newHistoryReturnWindow && newHistoryReturnWindow != node?.storeForwardConfig?.historyReturnWindow ?? -1 { hasChanges = true }
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

#Preview {
	StoreForwardConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
