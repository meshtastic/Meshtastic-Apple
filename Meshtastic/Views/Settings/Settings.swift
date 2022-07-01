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
	
	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "lastHeard", ascending: false)],
		animation: .default)

	private var nodes: FetchedResults<NodeInfoEntity>
	
	var body: some View {
		NavigationView {
			List {
				
				let connectedNodeNum = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.num : 0
				
				Section("General") {
					NavigationLink {
						AppSettings()
					} label: {
						
						Image(systemName: "gearshape")
							.symbolRenderingMode(.hierarchical)
						Text("App Settings")
					}
					Text("Apple app specific settings and features, app username, share position with mesh options, map and keyboard type, mesh log.")
						.font(.caption)
						.fixedSize(horizontal: false, vertical: true)
		
				}
				
				Section("Radio Configuration") {
					
					Text("Radio config views will be be enabled when there is a connected node. Save buttons will be enabled when there are config changes to save.")
						.font(.caption)
						.fixedSize(horizontal: false, vertical: true)
					
					NavigationLink {
						ShareChannel(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
						Image(systemName: "qrcode")
							.symbolRenderingMode(.hierarchical)
						Text("Share Channel QR Code")
					}
					.disabled(bleManager.connectedPeripheral == nil)
					
					NavigationLink {
						UserConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "person.crop.rectangle.fill")
							.symbolRenderingMode(.hierarchical)

						Text("User")
					}
					.disabled(bleManager.connectedPeripheral == nil)
					
					NavigationLink() {
						
						LoRaConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "dot.radiowaves.left.and.right")
							.symbolRenderingMode(.hierarchical)

						Text("LoRa")
					}
					.disabled(bleManager.connectedPeripheral == nil)
					
					NavigationLink {
						DeviceConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "flipphone")
							.symbolRenderingMode(.hierarchical)
						Text("Device")
					}
					.disabled(bleManager.connectedPeripheral == nil)
					
					NavigationLink {
						DisplayConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "display")
							.symbolRenderingMode(.hierarchical)
						Text("Display (Device Screen)")
					}
					.disabled(bleManager.connectedPeripheral == nil)
				
					NavigationLink {
						PositionConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "location")
							.symbolRenderingMode(.hierarchical)

						Text("Position")
					}
					.disabled(bleManager.connectedPeripheral == nil)
					
					Text("Default settings values are prefered whenever possible as they consume no bandwidth when sent over the mesh.")
						.font(.caption2)
						.fixedSize(horizontal: false, vertical: true)
				}
				Section("Module Configuration - Non Functional interaction preview.") {
					
					NavigationLink {
						CannedMessagesConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {

						Image(systemName: "list.bullet.rectangle.fill")
							.symbolRenderingMode(.hierarchical)

						Text("Canned Messages")
					}
					.disabled(bleManager.connectedPeripheral == nil)
					
					NavigationLink {
						ExternalNotificationConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "megaphone")
							.symbolRenderingMode(.hierarchical)

						Text("External Notification")
					}
					.disabled(bleManager.connectedPeripheral == nil)
					
					NavigationLink {
						RangeTestConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "point.3.connected.trianglepath.dotted")
							.symbolRenderingMode(.hierarchical)

						Text("Range Test (ESP32 Only)")
					}
					.disabled(bleManager.connectedPeripheral == nil)
						//nodes.first(where: { $0.num == connectedNodeNum })?.myInfo?.hasWifi ?? true)//||
						//	  nodes.first(where: { $0.num == connectedNodeNum })!.rangeTestConfig != nil)
					
					NavigationLink {
						SerialConfig()
					} label: {
					
						Image(systemName: "terminal")
							.symbolRenderingMode(.hierarchical)

						Text("Serial")
					}
					.disabled(false)
					

					NavigationLink {
						TelemetryConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "chart.xyaxis.line")
							.symbolRenderingMode(.hierarchical)

						Text("Telemetry (Sensors)")
					}
					.disabled(false)
				}
				// Not Implemented:
				// Store Forward Config - Not Working, TBEAM Only
				// WiFi Config - Would break connection to device
				// MQTT Config - Part of WiFi
			}
			.listStyle(GroupedListStyle())
			.navigationTitle("Settings")
			.onAppear {
				
			//	
				
			//	let connectedNode =

//				if nodes.first(where: { $0.num == (bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.num : 0) })!.rangeTestConfig == nil {
//					 
//					// We have no Range Test Config, go get it
//					self.bleManager.getModuleConfig(configType: AdminMessage.ModuleConfigType.rangetestConfig, destNum: bleManager.connectedPeripheral.num, wantResponse: tr)
//				}
			}
		}
	}
}
