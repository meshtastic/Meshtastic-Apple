//
//  TelemetryLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/7/22.
//
import SwiftUI

struct TelemetryLog: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity

	var body: some View {
		
		VStack {
		
			List {
				
				
				ForEach(node.telemetries!.array as! [TelemetryEntity], id: \.self) { (tel: TelemetryEntity) in
					
					VStack {
						
						if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {

							if tel.metricsType == 0 {
								
								HStack {
								
									Text("Device Metrics")
										.font(.title3)
									BatteryIcon(batteryLevel: tel.batteryLevel, font: .callout, color: .accentColor)
									
									if tel.batteryLevel == 0 {
										
										Text("Plugged In")
											.font(.callout)
											.foregroundColor(.gray)
										
									} else {
										
										Text("Battery Level: \(String(tel.batteryLevel))%")
											.font(.callout)
											.foregroundColor(.gray)
									}
									if tel.batteryLevel > 0 {
										
										Image(systemName: "bolt")
											.font(.callout)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
										Text("Voltage: \(String(tel.voltage))")
											.foregroundColor(.gray)
											.font(.callout)
									}
									Text("Channel Utilization: \(String(format: "%.2f", tel.channelUtilization))%")
										.foregroundColor(.gray)
										.font(.callout)
									
									Text("Airtime Utilization: \(String(format: "%.2f", tel.airUtilTx))%")
										.foregroundColor(.gray)
										.font(.callout)
									
									Image(systemName: "clock.badge.checkmark.fill")
											.font(.callout)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
									Text("Time:")
										.foregroundColor(.gray)
										.font(.callout)
									DateTimeText(dateTime: tel.time)
										.foregroundColor(.gray)
										.font(.callout)
								}
							}
							
						} else {
						
							HStack {
							
//								Image(systemName: "mappin.and.ellipse").foregroundColor(.accentColor) // .font(.subheadline)
//								Text("Lat/Long:").font(.caption)
//								Text("\(String(tel.batteryLevel ?? 0))")
//									.foregroundColor(.gray)
//									.font(.callout)

								Image(systemName: "arrow.up.arrow.down.circle")
									.font(.subheadline)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								Text("Alt:")
									.font(.caption)

								Text("\(String(tel.voltage))m")
									.foregroundColor(.gray)
									.font(.callout)
							}
						
							HStack {
							
								Image(systemName: "clock.badge.checkmark.fill")
									.font(.subheadline)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								Text("Time:")
									.font(.caption)
								DateTimeText(dateTime: tel.time)
									.foregroundColor(.gray)
									.font(.caption)

							}
						}
					}
				}
			}
		}
		.padding()
		.navigationTitle("Telemetry Log \(node.telemetries?.count ?? 0) Readings")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			self.bleManager.context = context
		}
	}
}
