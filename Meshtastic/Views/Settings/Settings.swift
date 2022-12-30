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
					Text("app.settings")
				}
				Section("radio.configuration") {
					
					NavigationLink {
						ShareChannels(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "qrcode")
							.symbolRenderingMode(.hierarchical)
						Text("share.channels")
					}
					
					NavigationLink {
						UserConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
					
						Image(systemName: "person.crop.rectangle.fill")
							.symbolRenderingMode(.hierarchical)

						Text("user")
					}
					
					NavigationLink() {
						
						LoRaConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
					
						Image(systemName: "dot.radiowaves.left.and.right")
							.symbolRenderingMode(.hierarchical)

						Text("lora")
					}
					
					NavigationLink() {

						Channels(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {

						Image(systemName: "fibrechannel")
							.symbolRenderingMode(.hierarchical)

						Text("channels")
					}
					
					NavigationLink() {
						
						BluetoothConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "antenna.radiowaves.left.and.right")
							.symbolRenderingMode(.hierarchical)
						Text("bluetooth")
					}
					
					NavigationLink {
						DeviceConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "flipphone")
							.symbolRenderingMode(.hierarchical)
						Text("device")
					}
					
					NavigationLink {
						DisplayConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "display")
							.symbolRenderingMode(.hierarchical)
						Text("display")
					}
					
					NavigationLink {
						NetworkConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
					
						Image(systemName: "network")
							.symbolRenderingMode(.hierarchical)
						Text("network")
					}
				
					NavigationLink {
						PositionConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
					
						Image(systemName: "location")
							.symbolRenderingMode(.hierarchical)
						Text("position")
					}
					
				}
				Section("module.configuration") {
					
					NavigationLink {
						CannedMessagesConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {

						Image(systemName: "list.bullet.rectangle.fill")
							.symbolRenderingMode(.hierarchical)

						Text("canned.messages")
					}
					
					NavigationLink {
						ExternalNotificationConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "megaphone")
							.symbolRenderingMode(.hierarchical)
						Text("external.notification")
					}
					NavigationLink {
						MQTTConfig(node: nodes.first(where: { $0.num == connectedNodeNum }))
					} label: {
						Image(systemName: "dot.radiowaves.right")
							.symbolRenderingMode(.hierarchical)
						Text("mqtt")
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
			Text("select.menu.item")
		}
	}
}
