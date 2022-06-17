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
	
//	var connectednode: NodeInfoEntity
	
	var body: some View {
		NavigationView {
			List {
				
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
				
				Section("Radio Configuration (Non-Functional Interaction Previews)") {
					
					NavigationLink {
						DeviceConfig()
					} label: {
					
						Image(systemName: "flipphone")
							.symbolRenderingMode(.hierarchical)
						Text("Device")
					}
					NavigationLink {
						DisplayConfig()
					} label: {
					
						Image(systemName: "display")
							.symbolRenderingMode(.hierarchical)
						Text("Display (Device Screen)")
					}
					NavigationLink {
						LoRaConfig()
					} label: {
					
						Image(systemName: "dot.radiowaves.left.and.right")
							.symbolRenderingMode(.hierarchical)

						Text("LoRa")
					}
					NavigationLink {
						PositionConfig()
					} label: {
					
						Image(systemName: "location")
							.symbolRenderingMode(.hierarchical)

						Text("Position")
					}
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
					NavigationLink {
						TelemetryConfig()
					} label: {
					
						Image(systemName: "chart.xyaxis.line")
							.symbolRenderingMode(.hierarchical)

						Text("Telemetry (Sensors)")
					}
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
