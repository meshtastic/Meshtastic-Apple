//
//  DeviceMetricsLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/7/22.
//
import SwiftUI

struct EnvironmentMetricsLog: View {
	
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
						
						Text("Temp")
							.font(.caption)
							.fontWeight(.bold)
						Text("Hum")
							.font(.caption)
							.fontWeight(.bold)
						Text("Bar")
							.font(.caption)
							.fontWeight(.bold)
						Text("Gas")
							.font(.caption)
							.fontWeight(.bold)
						Text("DC")
							.font(.caption)
							.fontWeight(.bold)
						Text("Volt")
							.font(.caption)
							.fontWeight(.bold)
						Text("Timestamp")
							.font(.caption)
							.fontWeight(.bold)
					}
					Divider()
					ForEach(node.telemetries!.reversed() as! [TelemetryEntity], id: \.self) { (em: TelemetryEntity) in
						
						if em.metricsType == 1 {
							
							let tempReadingType = (!(node.telemetryConfig?.environmentDisplayFahrenheit ?? false)) ? "°C" : "°F"
							
							GridRow {
								
								Text("\(String(format: "%.2f", em.temperature))\(tempReadingType)")
									.font(.caption)
								Text("\(String(format: "%.2f", em.relativeHumidity))")
									.font(.caption)
								Text("\(String(format: "%.2f", em.barometricPressure))")
									.font(.caption)
								Text("\(String(format: "%.2f", em.gasResistance))")
									.font(.caption)
								Text("\(String(format: "%.2f", em.current))")
									.font(.caption)
								Text("\(String(format: "%.2f", em.voltage))")
									.font(.caption)
								Text(em.time?.formattedDate(format: "MM/dd/yy hh:mm") ?? "Unknown time")
									.font(.caption)
							}
						}
					}
				}
				.padding(.leading, 15)
				.padding(.trailing, 5)
			}
		}
		Button {
						
			exportString = TelemetryToCsvFile(telemetry: node.telemetries!.array as! [TelemetryEntity], metricsType: 1)
			isExporting = true
			
		} label: {
			
			Label("Save", systemImage: "square.and.arrow.down")
		}
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.padding()
		.navigationTitle("Environment Metrics Log")
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
			defaultFilename: String("\(node.user!.longName ?? "Node") Environment Metrics Log"),
			onCompletion: { result in

				if case .success = result {
					
					print("Environment metrics log download succeeded.")
					
					self.isExporting = false
					
				} else {
					
					print("Environment metrics log download failed: \(result).")
				}
			}
		)
	}
}
