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
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "lastHeard", ascending: false)], animation: .default)
	private var nodes: FetchedResults<NodeInfoEntity>
	
	var body: some View {
		NavigationSplitView {
			List {
				let connectedNodeNum = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.num : 0
				
				NavigationLink() {
					AppSettings()
				} label: {

					Image(systemName: "gearshape")
						.symbolRenderingMode(.hierarchical)
					Text("App Settings")
				}
				Section("Radio Configuration") {
					
					NavigationLink {
						ShareChannels(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "qrcode")
							.symbolRenderingMode(.hierarchical)
						Text("Share Channels QR Code")
					}
					
					NavigationLink {
						UserConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
					
						Image(systemName: "person.crop.rectangle.fill")
							.symbolRenderingMode(.hierarchical)

						Text("User")
					}
					
					NavigationLink() {
						
						LoRaConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
					
						Image(systemName: "dot.radiowaves.left.and.right")
							.symbolRenderingMode(.hierarchical)

						Text("LoRa")
					}
					
					NavigationLink() {
						
						BluetoothConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "antenna.radiowaves.left.and.right")
							.symbolRenderingMode(.hierarchical)
						Text("Bluetooth (BLE)")
					}
					
					NavigationLink {
						DeviceConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "flipphone")
							.symbolRenderingMode(.hierarchical)
						Text("Device")
					}
					
					NavigationLink {
						DisplayConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "display")
							.symbolRenderingMode(.hierarchical)
						Text("Display (Device Screen)")
					}
					
					NavigationLink {
						NetworkConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
					
						Image(systemName: "network")
							.symbolRenderingMode(.hierarchical)
						Text("Network")
					}
				
					NavigationLink {
						PositionConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
					
						Image(systemName: "location")
							.symbolRenderingMode(.hierarchical)
						Text("Position")
					}
					
				}
				Section("Module Configuration") {
					
					NavigationLink {
						CannedMessagesConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {

						Image(systemName: "list.bullet.rectangle.fill")
							.symbolRenderingMode(.hierarchical)

						Text("Canned Messages")
					}
					
					NavigationLink {
						ExternalNotificationConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "megaphone")
							.symbolRenderingMode(.hierarchical)
						Text("External Notification")
					}
					NavigationLink {
						MQTTConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "dot.radiowaves.right")
							.symbolRenderingMode(.hierarchical)
						Text("MQTT")
					}
					NavigationLink {
						RangeTestConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "point.3.connected.trianglepath.dotted")
							.symbolRenderingMode(.hierarchical)
						Text("range.test")
					}
					NavigationLink {
						SerialConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "terminal")
							.symbolRenderingMode(.hierarchical)
						Text("serial")
					}
					NavigationLink {
						TelemetryConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "chart.xyaxis.line")
							.symbolRenderingMode(.hierarchical)
						Text("telemetry")
					}
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
						let connectedNode = nodes.first(where: { $0.num == connectedNodeNum })
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
				
			}
			.listStyle(GroupedListStyle())
			.navigationTitle("settings")
			.navigationBarItems(leading:
				MeshtasticLogo()
			)
		}
		detail: {
			Text("Select an item from the menu")
		}
	}
}
