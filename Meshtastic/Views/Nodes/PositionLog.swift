//
//  LocationHistory.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/5/22.
//
import SwiftUI

struct PositionLog: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State var isExporting = false
	@State var exportString = ""
	
	var node: NodeInfoEntity

	var body: some View {
		
		NavigationStack {
			
			ScrollView {
				
				Grid(alignment: .topLeading, horizontalSpacing: 2) {
					
					if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
						//Add a table for mac and ipad
					}
					
					GridRow {
						
						Text("Lat / Long")
							.font(.caption2)
							.fontWeight(.bold)
						Text("Sat")
							.font(.caption2)
							.fontWeight(.bold)
						Text("Alt")
							.font(.caption2)
							.fontWeight(.bold)
						Text("Spd")
							.font(.caption2)
							.fontWeight(.bold)
						Text("Hd")
							.font(.caption2)
							.fontWeight(.bold)
						Text("Timestamp")
							.font(.caption2)
							.fontWeight(.bold)
					}
					Divider()
					ForEach(node.positions!.reversed() as! [PositionEntity], id: \.self) { (mappin: PositionEntity) in
						GridRow {
							Text("\(String(mappin.latitude ?? 0)) \(String(mappin.longitude ?? 0))")
								.font(.caption2)
							Text(String(mappin.satsInView))
								.font(.caption2)
							Text(String(mappin.altitude))
								.font(.caption2)
							Text(String(mappin.speed))
								.font(.caption2)
							Text(String(mappin.heading))
								.font(.caption2)
							Text(mappin.time?.formattedDate(format: "MM/dd/yy hh:mm") ?? "Unknown time")
								.font(.caption2)
						}
					}
				}
				.padding(.leading, 15)
				.padding(.trailing, 5)
			}
			Button {
							
				exportString = PositionToCsvFile(positions: node.positions!.array as! [PositionEntity])
				isExporting = true
				
			} label: {
				
				Label("Save", systemImage: "square.and.arrow.down")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
		}
		.fileExporter(
			isPresented: $isExporting,
			document: CsvDocument(emptyCsv: exportString),
			contentType: .commaSeparatedText,
			defaultFilename: String("\(node.user?.longName ?? "Node") Position Log"),
			onCompletion: { result in

				if case .success = result {
					
					print("Position log download succeeded.")
					self.isExporting = false
					
				} else {
					
					print("Position log download failed: \(result).")
				}
			}
		)
		.navigationTitle("Position Log \(node.positions?.count ?? 0) Points")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			self.bleManager.context = context
		}
	}
}
