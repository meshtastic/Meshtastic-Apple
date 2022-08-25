//
//  LocationHistory.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/5/22.
//
import SwiftUI

struct LocationHistory: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State var isExporting = false
	@State var exportString = ""
	
	var node: NodeInfoEntity

	var body: some View {
		
		VStack {
		
			List {
				
				ForEach(node.positions!.reversed() as! [PositionEntity], id: \.self) { (mappin: PositionEntity) in
						
					VStack {
						
						if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {

							HStack {
							
								Image(systemName: "mappin.and.ellipse")
									.foregroundColor(.accentColor)
									.font(.callout)
								
								Text("Lat/Long:").font(.callout)
								Text("\(String(mappin.latitude ?? 0)) \(String(mappin.longitude ?? 0))")
									.foregroundColor(.gray)
									.font(.callout)

								Image(systemName: "arrow.up.arrow.down.circle")
									.font(.callout)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								Text("Alt:")
									.font(.callout)

								Text("\(String(mappin.altitude))m")
									.foregroundColor(.gray)
									.font(.callout)
								Image(systemName: "clock.badge.checkmark.fill")
									.font(.subheadline)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								Text("Time:")
									.font(.callout)
								DateTimeText(dateTime: mappin.time)
									.foregroundColor(.gray)
									.font(.callout)
								
							}
							
						} else {
						
							HStack {
							
								Image(systemName: "mappin.and.ellipse").foregroundColor(.accentColor) // .font(.subheadline)
								Text("Lat/Long:").font(.caption)
								Text("\(String(mappin.latitude ?? 0)) \(String(mappin.longitude ?? 0))")
									.foregroundColor(.gray)
									.font(.caption)

							}
						
							HStack {
							
								Image(systemName: "arrow.up.arrow.down.circle")
									.font(.subheadline)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								Text("Alt:")
									.font(.caption)
								Text("\(String(mappin.altitude))m")
									.foregroundColor(.gray)
									.font(.caption)
								Image(systemName: "clock.badge.checkmark.fill")
									.font(.subheadline)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								DateTimeText(dateTime: mappin.time)
									.foregroundColor(.gray)
									.font(.caption)
							}
						}
					}
				}
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
		.navigationTitle("Location History \(node.positions?.count ?? 0) Points")
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
