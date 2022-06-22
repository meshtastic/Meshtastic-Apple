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
					NavigationLink {
						ShareChannel()
					} label: {
						Image(systemName: "qrcode")
							.symbolRenderingMode(.hierarchical)
						Text("Share Channel QR Code")
					}
				}
				
				Section("Radio Configuration") {
					
					Text("Radio config views will be be enabled when there is a connected node. Save buttons will be enabled when there are config changes to save.")
						.font(.caption)
						.listRowSeparator(.visible)
						.fixedSize(horizontal: false, vertical: true)
					
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
					
					NavigationLink() {
						
						LoRaConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "dot.radiowaves.left.and.right")
							.symbolRenderingMode(.hierarchical)

						Text("LoRa")
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
					
//					NavigationLink {
//						PositionConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
//					} label: {
//
//						Image(systemName: "list.bullet.rectangle.fill")
//							.symbolRenderingMode(.hierarchical)
//
//						Text("Canned Messages")
//					}
					
					NavigationLink {
						ExternalNotificationConfig(node: nodes.first(where: { $0.num == connectedNodeNum }) ?? NodeInfoEntity())
					} label: {
					
						Image(systemName: "megaphone")
							.symbolRenderingMode(.hierarchical)

						Text("External Notification")
					}
					
					NavigationLink {
						RangeTestConfig()
					} label: {
					
						Image(systemName: "point.3.connected.trianglepath.dotted")
							.symbolRenderingMode(.hierarchical)

						Text("Range Test")
					}
					//.disabled(!(nodes.first(where: { $0.num == connectedNodeNum })?.myInfo?.hasWifi ?? true) || bleManager.connectedPeripheral == nil)
					
					NavigationLink {
						SerialConfig()
					} label: {
					
						Image(systemName: "terminal")
							.symbolRenderingMode(.hierarchical)

						Text("Serial")
					}
					.disabled(false)
					
					NavigationLink {
						TelemetryConfig()
					} label: {
					
						Image(systemName: "chart.xyaxis.line")
							.symbolRenderingMode(.hierarchical)

						Text("Telemetry (Sensors)")
					}
					.disabled(false)
				}
				// Not Implemented:
				// Store Forward Config - Not Working
				// WiFi Config - Would break connection to device
				// MQTT Config - Part of WiFi
			}
			.listStyle(GroupedListStyle())
			.navigationTitle("Settings")
		}
	}
}
