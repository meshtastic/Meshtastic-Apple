//
//  DeviceMetricsLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/7/22.
//
import SwiftUI

struct DeviceMetricsLog: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State var isExporting = false
	@State var exportString = ""
	
	var node: NodeInfoEntity

	var body: some View {
		
		NavigationStack {
			
			ScrollView {
				
				Grid(alignment: .topLeading, horizontalSpacing: 2) {
					
					GridRow {
						
						Text("Batt")
							.font(.callout)
							.fontWeight(.bold)
						Text("Voltage")
							.font(.callout)
							.fontWeight(.bold)
						Text("ChUtil")
							.font(.callout)
							.fontWeight(.bold)
						Text("AirTm")
							.font(.callout)
							.fontWeight(.bold)
						Text("Timestamp")
							.font(.callout)
							.fontWeight(.bold)
					}
					Divider()
					ForEach(node.telemetries!.reversed() as! [TelemetryEntity], id: \.self) { (dm: TelemetryEntity) in
						
						if dm.metricsType == 0 {
							
							GridRow {
								
								if dm.batteryLevel == 0 {
									
									Text("USB")
										.font(.callout)
									
								} else {
									
									Text("\(String(dm.batteryLevel))%")
										.font(.callout)
								}
								
								Text(String(dm.voltage))
									.font(.callout)
								Text("\(String(format: "%.2f", dm.channelUtilization))%")
									.font(.callout)
								Text("\(String(format: "%.2f", dm.airUtilTx))%")
									.font(.callout)
								Text(dm.time?.formattedDate(format: "MM/dd/yy hh:mm") ?? "Unknown time")
									.font(.callout)
							}
						}
					}
				}
				.padding(.leading, 15)
				.padding(.trailing, 5)
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
		.navigationTitle("Device Metrics Log")
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
			defaultFilename: String("\(node.user!.longName ?? "Node") Device Telemetry Log"),
			onCompletion: { result in

				if case .success = result {
					
					print("Device Telemetry log download succeeded.")
					
					self.isExporting = false
					
				} else {
					
					print("Device Telemetry log download failed: \(result).")
				}
			}
		)
	}
}
