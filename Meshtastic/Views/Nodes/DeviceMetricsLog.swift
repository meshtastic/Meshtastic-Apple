//
//  DeviceMetricsLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/7/22.
//
import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct DeviceMetricsLog: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State private var isPresentingClearLogConfirm: Bool = false
	
	@State var isExporting = false
	@State var exportString = ""
	
	var node: NodeInfoEntity
	
	struct MountPrice: Identifiable {
		var id = UUID()
		var mount: String
		var value: Double
	}

	var body: some View {
		NavigationStack {
			let oneDayAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())
			let data = node.telemetries!.filtered(using: NSPredicate(format: "metricsType == 0 && time !=nil && time >= %@", oneDayAgo! as CVarArg))
			if data.count > 0 {
				GroupBox(label:	Label("Battery Level Trend", systemImage: "battery.100")) {
					Chart(data.array as! [TelemetryEntity], id: \.self) {
						LineMark(
							x: .value("Hour", $0.time!.formattedDate(format: "ha")),
							y: .value("Value", $0.batteryLevel)
						)
						PointMark(
							x: .value("Hour", $0.time!.formattedDate(format: "ha")),
							y: .value("Value", $0.batteryLevel)
						)
					}
					.frame(height: 150)
				}
			}
			if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
				//Add a table for mac and ipad
				Table(node.telemetries!.reversed() as! [TelemetryEntity]) {
					
					TableColumn("Battery Level") { dm in
						
						if dm.metricsType == 0 {
							if dm.batteryLevel == 0 {
								
								Text("Powered")
								
							} else {
								
								Text("\(String(dm.batteryLevel))%")
							}
						}
					}
					TableColumn("Voltage") { dm in
						Text(String(format: "%.6f", dm.voltage ?? 0))
					}
					TableColumn("Channel Utilization") { dm in
						Text(String(format: "%.2f", dm.channelUtilization))
					}
					TableColumn("Airtime") { dm in
						Text("\(String(format: "%.2f", dm.airUtilTx))%")
					}
					TableColumn("Time Stamp") { dm in
						Text(dm.time?.formattedDate(format: "MM/dd/yy hh:mm") ?? "Unknown time")
					}
				}
				
			} else {
				
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
		}
		HStack {
			
			Button(role: .destructive) {
							
				isPresentingClearLogConfirm = true
				
			} label: {
				
				Label("Clear Log", systemImage: "trash.fill")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				"Are you sure?",
				isPresented: $isPresentingClearLogConfirm,
				titleVisibility: .visible
			) {
				Button("Delete all device metrics?", role: .destructive) {
					
					if clearTelemetry(destNum: node.num, metricsType: 0, context: context) {
						
						print("Clear Device Metrics Log Failed")
						
					} else {
						
						
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
		}
			
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
