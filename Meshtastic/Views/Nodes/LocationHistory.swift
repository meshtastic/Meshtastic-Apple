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
	
	var node: NodeInfoEntity

	var body: some View {
		
		VStack {
		
			List {
				
				ForEach(node.positions!.array as! [PositionEntity], id: \.self) { (mappin: PositionEntity) in
						
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

								Image(systemName: "arrow.up.arrow.down.circle")
									.font(.subheadline)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								Text("Alt:")
									.font(.caption)

								Text("\(String(mappin.altitude))m")
									.foregroundColor(.gray)
									.font(.caption)
							}
						
							HStack {
							
								Image(systemName: "clock.badge.checkmark.fill")
									.font(.subheadline)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								Text("Time:")
									.font(.caption)
								DateTimeText(dateTime: mappin.time)
									.foregroundColor(.gray)
									.font(.caption)

							}
						}
					}
				}
			}
		}
		.padding()
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
