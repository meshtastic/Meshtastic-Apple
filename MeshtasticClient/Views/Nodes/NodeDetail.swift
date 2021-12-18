/*
Abstract:
A view showing the details for a node.
*/

import SwiftUI
import MapKit
import CoreLocation

struct NodeDetail: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	var node: NodeInfoEntity

	var body: some View {
		
		let mostRecent = node.positions?.lastObject as! PositionEntity

		GeometryReader { bounds in

			VStack {

				if node.positions != nil && node.positions!.count > 0 {

					let nodeCoordinatePosition = CLLocationCoordinate2D(latitude: mostRecent.latitude!, longitude: mostRecent.longitude!)

					let regionBinding = Binding<MKCoordinateRegion>(
						get: {
							MKCoordinateRegion(center: nodeCoordinatePosition, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
						},
						set: { _ in }
					)
					let annotations = [MapLocation(name: node.user!.shortName ?? "???", coordinate: mostRecent.coordinate!)]

					Map(coordinateRegion: regionBinding, showsUserLocation: true, userTrackingMode: .none, annotationItems: annotations) { location in
						MapAnnotation(
						   coordinate: location.coordinate,
						   content: {
							   CircleText(text: node.user!.shortName ?? "???", color: .accentColor)
						   }
						)
					}
					.frame(idealWidth: bounds.size.width, maxHeight: bounds.size.height / 3)
					
				} else {
					
					Image(node.user?.hwModel ?? "UNSET")
						.resizable()
						.aspectRatio(contentMode: .fit)
						.frame(width: bounds.size.width, height: bounds.size.height / 3)
				}

				ScrollView {
					
					if node.lastHeard != nil {

						HStack {

							Image(systemName: "clock").font(.title2).foregroundColor(.accentColor)
							Text("Last Heard: \(node.lastHeard!, style: .relative) ago").font(.title3)
						}
						.padding()
						Divider()
					}

					HStack {

						VStack(alignment: .center) {
							Text("AKA").font(.title2).fixedSize()
							CircleText(text: node.user?.shortName ?? "???", color: .accentColor)
								.offset(y: 10)
						}
						.padding([.leading, .trailing, .bottom])
						Divider()
						VStack {
							
							Image(node.user!.hwModel ?? "UNSET")
								.resizable()
								.frame(width: 50, height: 50)
								.cornerRadius(5)

							Text(String(node.user!.hwModel ?? "UNSET"))
								.font(.subheadline).fixedSize()
						}
						.padding()
						
						if true {//node.snr > 0 {
							Divider()
							VStack(alignment: .center) {

								Image(systemName: "waveform.path")
									.font(.title)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								Text("SNR").font(.title2).fixedSize()
								Text(String(node.snr))
									.font(.title2)
									.foregroundColor(.gray)
									.fixedSize()
							}
							.padding([.leading, .trailing, .bottom])
						}
						
						if node.positions!.count > 0 {
							Divider()
						
							VStack(alignment: .center) {
							
								BatteryIcon(batteryLevel: mostRecent.batteryLevel, font: .title, color: .accentColor)
									.padding(.bottom)
								if mostRecent.batteryLevel > 0 {
									
									Text("Battery").font(.title2).fixedSize()
									Text(String(mostRecent.batteryLevel) + "%")
										.font(.title2)
										.foregroundColor(.gray)
										.symbolRenderingMode(.hierarchical)
								} else {
									
									Text("Powered")
										.font(.callout)
										.fixedSize()
								}
							}
							.padding([.leading, .trailing, .bottom])
						}
					}
					.padding(4)
					
					Divider()

					HStack(alignment: .center) {
						VStack {
							HStack {
								Image(systemName: "person").font(.title3).foregroundColor(.accentColor)
								Text("Unique Id:").font(.title3)
							}
							Text(node.user?.userId ?? "??????").font(.headline).foregroundColor(.gray)
						}
						Divider()
						VStack {
							HStack {
							Image(systemName: "number").font(.title3).foregroundColor(.accentColor)
								Text("Node Number:").font(.title3)
							}
							Text(String(node.num)).font(.headline).foregroundColor(.gray)
						}
					}.padding()
					
					if node.positions != nil && node.positions!.count > 0 {
						
						Divider()
						
						HStack {
							
							Image(systemName: "map.circle.fill").font(.title).foregroundColor(.accentColor)
							Text("Position History (\(node.positions?.count ?? 0) Points)").font(.title2)
						}
						.padding()
						
						Divider()
						
						ForEach(node.positions!.array as! [PositionEntity], id: \.self) { (mappin: PositionEntity) in

							VStack {
								
								HStack {
									
									Image(systemName: "mappin.and.ellipse").foregroundColor(.accentColor) //.font(.subheadline)
									Text("Lat/Long:").font(.caption)
									Text("\(String(mappin.latitude ?? 0)) \(String(mappin.longitude ?? 0))")
										.foregroundColor(.gray)
										.font(.caption)
										
									Text("Altitude:")
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
									Text("\(mappin.time!, style: .date) \(mappin.time!, style: .time)")
										.foregroundColor(.gray)
										.font(.caption)
									Divider()
									
									Text("Battery").font(.caption).fixedSize()
									Text(String(mappin.batteryLevel) + "%")
										.font(.caption)
										.foregroundColor(.gray)
										.symbolRenderingMode(.hierarchical)
								}
							}
							.padding([.top, .bottom])
							Divider()
						}
					}
				}
			}.navigationTitle(node.user!.longName ?? "Unknown")
			.navigationBarTitleDisplayMode(.inline)
			.navigationBarItems(trailing:

			ZStack {

				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName :
						"???")
			})
			.onAppear(perform: {

				self.bleManager.context = context

			})
		}
		.ignoresSafeArea(.all, edges: [.leading, .trailing])
	}
}

struct NodeInfoEntityDetail_Previews: PreviewProvider {
	
	static let bleManager = BLEManager()

	static var previews: some View {
		Group {
			
			//NodeDetail(node: node)
		}
	}
}
