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
					
					NavigationLink {
						DeviceConfig()
					} label: {
					
						Image(systemName: "flipphone")
							.symbolRenderingMode(.hierarchical)
						Text("Device")
					}
					.disabled(bleManager.connectedPeripheral == nil)
					
					NavigationLink {
						DisplayConfig()
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
				}
				Section("Module Configuration") {
					
					NavigationLink {
						DisplayConfig()
					} label: {
					
						Image(systemName: "list.bullet.rectangle.fill")
							.symbolRenderingMode(.hierarchical)

						Text("Canned Messages")
					}
					.disabled(true)
					NavigationLink {
						RangeTestConfig()
					} label: {
					
						Image(systemName: "point.3.connected.trianglepath.dotted")
							.symbolRenderingMode(.hierarchical)

						Text("Range Test")
					}
					.disabled(!(nodes.first(where: { $0.num == connectedNodeNum })?.myInfo?.hasWifi ?? true) || bleManager.connectedPeripheral == nil)
					
					NavigationLink {
						TelemetryConfig()
					} label: {
					
						Image(systemName: "chart.xyaxis.line")
							.symbolRenderingMode(.hierarchical)

						Text("Telemetry (Sensors)")
					}
					.disabled(true)
				}
				// Not Implemented:
				// External Notifications - Not Working
				// Serial Config - Not sure what the point is
				// Store Forward Config - Not Working
				// WiFi Config - Would break connection to device
				// MQTT Config - Part of WiFi
			}
			.listStyle(GroupedListStyle())
			.navigationTitle("Settings")
		}
	}
}
