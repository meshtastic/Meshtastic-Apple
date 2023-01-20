//
//  Settings.swift
//  MeshtasticApple
//
//  Copyright (c) Garth Vander Houwen 6/9/22.
//

import SwiftUI

struct Settings: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "user.longName", ascending: true)], animation: .default)
	private var nodes: FetchedResults<NodeInfoEntity>
	@State private var selectedNode: Int = 0
	@State private var connectedNodeNum: Int = 0
	@State private var initialLoad: Bool = true
	
	var body: some View {
		NavigationSplitView {
			List {
				NavigationLink() {
					AppSettings()
				} label: {
					Image(systemName: "gearshape")
						.symbolRenderingMode(.hierarchical)
					Text("app.settings")
				}
				Section("Configure") {
					Picker("Configuring Node", selection: $selectedNode) {
						if connectedNodeNum == 0 {
							Text("Connect to a Node").tag(0)
						}
						ForEach(nodes) { node in
							if node.num == bleManager.connectedPeripheral?.num ?? 0 {
								Text("BLE Config: \(node.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown"))")
									.tag(Int(node.num))
							} else if node.metadata != nil {
								Text("Remote Config: \(node.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown"))")
									.tag(Int(node.num))
							} else {
								Text("Request Admin: \(node.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown"))")
									.tag(Int(node.num))
							}
						}
					}
					.pickerStyle(.menu)
					.labelsHidden()
					.onChange(of: selectedNode) { newValue in
						if selectedNode > 0 {
							let node = nodes.first(where: { $0.num == newValue })
							let connectedNode = nodes.first(where: { $0.num == connectedNodeNum })
							connectedNodeNum = Int(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.num : 0)
							
							if node?.metadata == nil && node!.num != connectedNodeNum {
								let adminMessageId =  bleManager.requestDeviceMetadata(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode!.myInfo!.adminIndex, context: context)
									
								if adminMessageId > 0 {
									print("Saved node metadata")
								}
							}
						}
					}
				}
				
				Section("radio.configuration") {
					
					NavigationLink {
						ShareChannels(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "qrcode")
							.symbolRenderingMode(.hierarchical)
						Text("share.channels")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					NavigationLink {
						UserConfig(node: nodes.first(where: { $0.num == selectedNode }), connectedNode: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
					
						Image(systemName: "person.crop.rectangle.fill")
							.symbolRenderingMode(.hierarchical)
						Text("user")
					}
					.disabled(selectedNode == 0)
					
					NavigationLink() {
						LoRaConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
						Image(systemName: "dot.radiowaves.left.and.right")
							.symbolRenderingMode(.hierarchical)
						Text("lora")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink() {
						Channels(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "fibrechannel")
							.symbolRenderingMode(.hierarchical)
						Text("channels")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink() {
						BluetoothConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
						Image(systemName: "antenna.radiowaves.left.and.right")
							.symbolRenderingMode(.hierarchical)
						Text("bluetooth")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink {
						DeviceConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
						Image(systemName: "flipphone")
							.symbolRenderingMode(.hierarchical)
						Text("device")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink {
						DisplayConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
						Image(systemName: "display")
							.symbolRenderingMode(.hierarchical)
						Text("display")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink {
						NetworkConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
					
						Image(systemName: "network")
							.symbolRenderingMode(.hierarchical)
						Text("network")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
				
					NavigationLink {
						PositionConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
					
						Image(systemName: "location")
							.symbolRenderingMode(.hierarchical)
						Text("position")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
				}
				Section("module.configuration") {
					
					NavigationLink {
						CannedMessagesConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {

						Image(systemName: "list.bullet.rectangle.fill")
							.symbolRenderingMode(.hierarchical)

						Text("canned.messages")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink {
						ExternalNotificationConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
						Image(systemName: "megaphone")
							.symbolRenderingMode(.hierarchical)
						Text("external.notification")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink {
						MQTTConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
						Image(systemName: "dot.radiowaves.right")
							.symbolRenderingMode(.hierarchical)
						Text("mqtt")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink {
						RangeTestConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
						Image(systemName: "point.3.connected.trianglepath.dotted")
							.symbolRenderingMode(.hierarchical)
						Text("range.test")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink {
						SerialConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
						Image(systemName: "terminal")
							.symbolRenderingMode(.hierarchical)
						Text("serial")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
					
					NavigationLink {
						TelemetryConfig(node: nodes.first(where: { $0.num == selectedNode }))
					} label: {
						Image(systemName: "chart.xyaxis.line")
							.symbolRenderingMode(.hierarchical)
						Text("telemetry")
					}
					.disabled(selectedNode > 0 && selectedNode != connectedNodeNum)
				}
				Section(header: Text("logging")) {
					NavigationLink {
						MeshLog()
					} label: {
						Image(systemName: "list.bullet.rectangle")
							.symbolRenderingMode(.hierarchical)
						Text("mesh.log")
					}
					NavigationLink {
						let connectedNode = nodes.first(where: { $0.num == selectedNode })
						AdminMessageList(user: connectedNode?.user)
					} label: {
						Image(systemName: "building.columns")
							.symbolRenderingMode(.hierarchical)
						Text("admin.log")
					}
				}
				Section(header: Text("about")) {
					NavigationLink {
						AboutMeshtastic()
					} label: {
						Image(systemName: "questionmark.app")
							.symbolRenderingMode(.hierarchical)
						
						Text("about.meshtastic")
					}
				}
			}
			.onAppear {
				self.bleManager.context = context
				self.bleManager.userSettings = userSettings
				if initialLoad {
					selectedNode = Int(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.num : 0)
					initialLoad = false
				}
				connectedNodeNum = Int(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.num : 0)
				//let node = nodes.first(where: { $0.num == connectedNodeNum })
				//selectedNode = node?.num ?? 0
			}
			.listStyle(GroupedListStyle())
			.navigationTitle("settings")
			.navigationBarItems(leading:
				MeshtasticLogo()
			)
		}
		detail: {
			Text("select.menu.item")
		}
	}
}
