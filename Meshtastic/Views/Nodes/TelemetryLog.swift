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
	
	@State var isExporting = false
	@State var exportString = ""
	
	var node: NodeInfoEntity

	var body: some View {
		
		List {
			
			ForEach(node.telemetries!.array as! [TelemetryEntity], id: \.self) { (tel: TelemetryEntity) in
				
				VStack (alignment: .leading)  {
					
					if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {

						
						if tel.metricsType == 0 {
							
							// Device Metrics
							HStack {
							
								Text("Device Metrics")
									.font(.title)
								
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
							
						} else if tel.metricsType == 1 {
							
							// Environment Metrics
							HStack {
							
								Text("Environment Metrics")
									.font(.title)
								
								
								let tempReadingType = (!(node.telemetryConfig?.environmentDisplayFahrenheit ?? true)) ? "°C" : "°F"
								
								if  tel.temperature > 0 {
									
									Image(systemName: "thermometer")
											.font(.callout)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
									Text("Temperature: \(String(format: "%.2f", tel.temperature))\(tempReadingType)")
										.foregroundColor(.gray)
										.font(.callout)
								}
																	
								if tel.relativeHumidity > 0 {
									
									Image(systemName: "humidity")
											.font(.callout)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
									Text("Relative Humidity: \(String(format: "%.2f", tel.relativeHumidity))")
										.foregroundColor(.gray)
										.font(.callout)
								}
								
								if tel.barometricPressure > 0 {
									
									Image(systemName: "barometer")
											.font(.callout)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
									Text("Barometric Pressure: \(String(format: "%.2f", tel.barometricPressure))")
										.foregroundColor(.gray)
										.font(.callout)
								}
								
								if tel.gasResistance > 0 {
									
									Image(systemName: "aqi.medium")
											.font(.callout)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
									Text("Gas Resistance: \(String(format: "%.2f", tel.gasResistance))")
										.foregroundColor(.gray)
										.font(.callout)
								}
								
								if  tel.current > 0 {
									
									Image(systemName: "directcurrent")
											.font(.callout)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
									Text("Current: \(String(format: "%.2f", tel.current))")
										.foregroundColor(.gray)
										.font(.callout)
									
									Image(systemName: "bolt")
											.font(.callout)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
									Text("Voltage: \(String(format: "%.2f", tel.voltage))")
										.foregroundColor(.gray)
										.font(.callout)
								}
								
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
					
						if tel.metricsType == 0 {
							
							// Device Metrics iPhone Template
							VStack {
								
								HStack {
									
									Spacer()
									Text("Device Metrics")
										.font(.title)
									Spacer()
								}
								
									
								HStack {
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
								}
								HStack {
									if tel.batteryLevel > 0 {
										
										Image(systemName: "bolt")
											.font(.callout)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
										Text("Voltage: \(String(tel.voltage))")
											.foregroundColor(.gray)
											.font(.callout)
									}
								}
								
								Text("Channel Utilization: \(String(format: "%.2f", tel.channelUtilization))%")
									.foregroundColor(.gray)
									.font(.callout)
								
								Text("Airtime Utilization: \(String(format: "%.2f", tel.airUtilTx))%")
									.foregroundColor(.gray)
									.font(.callout)
								HStack {
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
						} else if tel.metricsType == 1 {
							
							// Environment Metrics
							
							let tempReadingType = (!(node.telemetryConfig?.environmentDisplayFahrenheit ?? true)) ? "°C" : "°F"
							
							
							// Environment Metrics iPhone Template
							VStack {
							
								HStack {
									
									Spacer()
									Text("Environment Metrics")
										.font(.title3)
									Spacer()
								}
								
								HStack {
								
									if  tel.temperature > 0 {
										
										Image(systemName: "thermometer")
												.font(.callout)
												.foregroundColor(.accentColor)
												.symbolRenderingMode(.hierarchical)
										Text("Temperature: \(String(format: "%.2f", tel.temperature))\(tempReadingType)")
											.foregroundColor(.gray)
											.font(.callout)
									}
								}
								
								HStack {
									
									if  tel.relativeHumidity > 0 {
										
										Image(systemName: "humidity")
												.font(.callout)
												.foregroundColor(.accentColor)
												.symbolRenderingMode(.hierarchical)
										Text("Relative Humidity: \(String(format: "%.2f", tel.relativeHumidity))")
											.foregroundColor(.gray)
											.font(.callout)
									}
								}
								
								if  tel.current > 0 {
									
									HStack {
										
										Image(systemName: "directcurrent")
												.font(.callout)
												.foregroundColor(.accentColor)
												.symbolRenderingMode(.hierarchical)
										Text("Current: \(String(format: "%.2f", tel.current))")
											.foregroundColor(.gray)
											.font(.callout)
									}
									
									HStack {
										
										Image(systemName: "bolt")
												.font(.callout)
												.foregroundColor(.accentColor)
												.symbolRenderingMode(.hierarchical)
										Text("Voltage: \(String(format: "%.2f", tel.voltage))")
											.foregroundColor(.gray)
											.font(.callout)
									}
								}
								
								if  tel.barometricPressure > 0 {
									
									HStack {
										
										Image(systemName: "barometer")
												.font(.callout)
												.foregroundColor(.accentColor)
												.symbolRenderingMode(.hierarchical)
										Text("Barometric Pressure: \(String(format: "%.2f", tel.barometricPressure))")
											.foregroundColor(.gray)
											.font(.callout)
									}
								}
								
								if tel.gasResistance > 0 {
									
									HStack {
									
										Image(systemName: "aqi.medium")
												.font(.callout)
												.foregroundColor(.accentColor)
												.symbolRenderingMode(.hierarchical)
										Text("Gas Resistance: \(String(format: "%.2f", tel.gasResistance))")
											.foregroundColor(.gray)
											.font(.callout)
									}
								}
								
								HStack {
									
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
						}
					}
				}
			}
		}
		Button {
						
			exportString = TelemetryToCsvFile(telemetry: node.telemetries!.array as! [TelemetryEntity], metricsType: 0)
			isExporting = true
			
		} label: {
			
			Label("Save", systemImage: "square.and.arrow.down")
		}
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
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
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user!.longName ?? "Node") Telemetry Log"),
			onCompletion: { result in

				if case .success = result {
					
					print("Telemetry log download succeeded.")
					
					self.isExporting = false
					
				} else {
					
					print("Telemetry log download failed: \(result).")
				}
			}
		)
	}
}
