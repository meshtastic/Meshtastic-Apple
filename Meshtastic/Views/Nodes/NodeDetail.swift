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
	
	@State var initialLoad: Bool = true
	@State var satsInView = 0
	@State private var isPresentingShutdownConfirm: Bool = false
	@State private var isPresentingRebootConfirm: Bool = false

	var node: NodeInfoEntity

	var body: some View {
		
		let hwModelString = node.user?.hwModel ?? "UNSET"

		HStack {

			GeometryReader { bounds in

				VStack {

					if node.positions?.count ?? 0 > 0 {
					
						let mostRecent = node.positions?.lastObject as! PositionEntity

						if mostRecent.coordinate != nil {

							let nodeCoordinatePosition = CLLocationCoordinate2D(latitude: mostRecent.latitude!, longitude: mostRecent.longitude!)

							let regionBinding = Binding<MKCoordinateRegion>(
								get: {
									MKCoordinateRegion(center: nodeCoordinatePosition, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
								},
								set: { _ in }
							)
							
							ZStack {
								
								let annotations = node.positions?.array as! [PositionEntity]
								
								Map(coordinateRegion: regionBinding,
									interactionModes: [.all],
									showsUserLocation: true,
									userTrackingMode: .constant(.follow),
									annotationItems: annotations)
								{ location in
									
									return MapAnnotation(
									   coordinate: location.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
									   content: {
										   
										   NodeAnnotation(time: location.time!)
									   }
									)
								 }
							    .ignoresSafeArea(.all, edges: [.leading, .trailing])
								.frame(idealWidth: bounds.size.width, minHeight: bounds.size.height / 2)
							}
						}
						//Text("\(mostRecent.satsInView)")
					} else {
						
						Image(node.user?.hwModel ?? "UNSET")
							.resizable()
							.aspectRatio(contentMode: .fit)
							.cornerRadius(10)
							.frame(width: bounds.size.width, height: bounds.size.height / 2)
					}
					
					ScrollView {
																	
						if self.bleManager.connectedPeripheral != nil && self.bleManager.connectedPeripheral.num == node.num && self.bleManager.connectedPeripheral.num == node.num {
							
							Divider()
							HStack {
								
								if  hwModelString == "TBEAM" || hwModelString == "TECHO" || hwModelString.contains("4631") {
								
									Button(action: {
										
										isPresentingShutdownConfirm = true
									}) {
											
										Label("Power Off", systemImage: "power")
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.large)
									.padding()
									.confirmationDialog(
										"Are you sure?",
										isPresented: $isPresentingShutdownConfirm
									) {
										Button("Shutdown Node?", role: .destructive) {
											
											if !bleManager.sendShutdown(destNum: node.num) {
												
												print("Shutdown Failed")
											}
										}
									}
								}
							
								Button(action: {
									
									isPresentingRebootConfirm = true
									
								}) {
				
									Label("Reboot", systemImage: "arrow.triangle.2.circlepath")
								}
								.buttonStyle(.bordered)
								.buttonBorderShape(.capsule)
								.controlSize(.large)
								.padding()
								.confirmationDialog(
									
									"Are you sure?",
									isPresented: $isPresentingRebootConfirm
									) {
										
									Button("Reboot Node?", role: .destructive) {
										
										if !bleManager.sendReboot(destNum: node.num) {
											
											print("Reboot Failed")
										}
									}
								}
							}
							.padding(5)
						}
						
						if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
							
							// Add a divider if there is no map
							if (node.positions?.count ?? 0) == 0 {
								
								Divider()
							}
							
							HStack {
								
								VStack(alignment: .center) {
									
									Text("AKA").font(.largeTitle)
										.foregroundColor(.gray).fixedSize()
										.offset(y:20)
									CircleText(text: node.user?.shortName ?? "???", color: .accentColor, circleSize: 75, fontSize: 26)
								}
								.padding()

								Divider()

								VStack {

									if node.user != nil {
										
										Image(hwModelString)
											.resizable()
											.frame(width: 90, height: 90)
											.cornerRadius(5)

										Text(String(hwModelString))
											.foregroundColor(.gray)
											.font(.largeTitle).fixedSize()
									}
								}
								.padding()
								
								
								if node.snr > 0 {
									Divider()
									VStack(alignment: .center) {

										Image(systemName: "waveform.path")
											.font(.title)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
											.padding(.bottom, 10)
										Text("SNR").font(.largeTitle).fixedSize()
										Text(String(node.snr))
											.font(.largeTitle)
											.foregroundColor(.gray)
											.fixedSize()
									}
								}

								if node.telemetries?.count ?? 0 >= 1 {

									let mostRecent = node.telemetries?.lastObject as! TelemetryEntity

									Divider()

									VStack(alignment: .center) {

										BatteryIcon(batteryLevel: mostRecent.batteryLevel, font: .largeTitle, color: .accentColor)
											.padding(.bottom, 10)
										
										if mostRecent.batteryLevel > 0 {
											Text(String(mostRecent.batteryLevel) + "%")
												.font(.largeTitle)
												.frame(width: 100)
												.foregroundColor(.gray)
												.fixedSize()
										}
										if mostRecent.voltage > 0 {
											
											Text(String(format: "%.2f", mostRecent.voltage) + " V")
												.font(.largeTitle)
												.foregroundColor(.gray)
												.fixedSize()
										}
									}
									.padding()
								}
								Divider()
							}
							.padding()
							
							HStack(alignment: .center) {
								
								VStack {
									HStack {
										Image(systemName: "person")
											.font(.title)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
										Text("User Id:").font(.title)
									}
									Text(node.user?.userId ?? "??????").font(.title).foregroundColor(.gray)
								}
								Divider()
								VStack {
									HStack {
									Image(systemName: "number")
											.font(.title2)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
										Text("Node Number:").font(.title)
									}
									Text(String(node.num)).font(.title).foregroundColor(.gray)
								}
								Divider()
								VStack{
									HStack {
										Image(systemName: "globe")
											.font(.title)
												.foregroundColor(.accentColor)
												.symbolRenderingMode(.hierarchical)
										Text("MAC Address: ").font(.title)
										
									}
									Text(String(node.user?.macaddr?.macAddressString ?? "not a valid mac address"))
										.font(.title)
										.foregroundColor(.gray)
								}
								Divider()
								VStack{
									HStack {
										Image(systemName: "clock.badge.checkmark.fill")
											.font(.title)
												.foregroundColor(.accentColor)
												.symbolRenderingMode(.hierarchical)
										Text("Last Heard: ").font(.title)
										
									}
									DateTimeText(dateTime: node.lastHeard)
										.font(.title)
										.foregroundColor(.gray)
								}
							}
							.padding()
							Divider()
							
						} else {
							
							HStack {

								VStack(alignment: .center) {
									Text("AKA").font(.title2).fixedSize()
									CircleText(text: node.user?.shortName ?? "???", color: .accentColor)
										.offset(y: 10)
								}
								.padding(5)

								Divider()

								VStack {

									if node.user != nil {
										
										Image(node.user!.hwModel ?? "UNSET")
											.resizable()
											.frame(width: 50, height: 50)
											.cornerRadius(5)

										Text(String(node.user!.hwModel ?? "UNSET"))
											.font(.callout).fixedSize()
									}
								}
								.padding(5)
								
								
								if node.snr > 0 {
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
									.padding(5)
								}

								if node.telemetries?.count ?? 0 >= 1 {

									let mostRecent = node.telemetries?.lastObject as! TelemetryEntity

									Divider()

									VStack(alignment: .center) {

										BatteryIcon(batteryLevel: mostRecent.batteryLevel, font: .title, color: .accentColor)
											.padding(.bottom)
										
										if mostRecent.batteryLevel > 0 {
											Text(String(mostRecent.batteryLevel) + "%")
												.font(.title3)
												.foregroundColor(.gray)
												.fixedSize()
										}
										if mostRecent.voltage > 0 {
											
											Text(String(format: "%.2f", mostRecent.voltage) + " V")
												.font(.title3)
												.foregroundColor(.gray)
												.fixedSize()
										}
									}
									.padding(5)
								}
							}
							.padding(4)
							
							Divider()
							
							HStack(alignment: .center) {
								VStack {
									HStack {
										Image(systemName: "person")
											.font(.title2)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
										Text("User Id:").font(.title2)
									}
									Text(node.user?.userId ?? "??????").font(.title3).foregroundColor(.gray)
								}
								Divider()
								VStack {
									HStack {
									Image(systemName: "number")
											.font(.title2)
											.foregroundColor(.accentColor)
											.symbolRenderingMode(.hierarchical)
										Text("Node Number:").font(.title2)
									}
									Text(String(node.num)).font(.title3).foregroundColor(.gray)
								}
							}
							.padding(5)
							Divider()
							HStack {
								Image(systemName: "globe")
										.font(.headline)
										.foregroundColor(.accentColor)
										.symbolRenderingMode(.hierarchical)
								Text("MAC Address: ")
								Text(String(node.user?.macaddr?.macAddressString ?? "not a valid mac address")).foregroundColor(.gray)
							}
						}
						
						List {
							
							if (node.positions?.count ?? 0) > 0 {
								
								NavigationLink {
									LocationHistory(node: node)
								} label: {

									Image(systemName: "building.columns")
										.symbolRenderingMode(.hierarchical)
										.font(.title)

									Text("Position History \(node.positions?.count ?? 0) Points")
										.font(.title3)
								}
								.fixedSize(horizontal: false, vertical: true)
							}
							if (node.telemetries?.count ?? 0) > 0 {
								NavigationLink {
									TelemetryLog(node: node)
								} label: {

									Image(systemName: "chart.xyaxis.line")
										.symbolRenderingMode(.hierarchical)
										.font(.title)

									Text("Telemetry Log \(node.telemetries?.count ?? 0) Readings")
										.font(.title3)
								}
								.fixedSize(horizontal: false, vertical: true)
							}
						}
						.listStyle(GroupedListStyle())
						.frame(minHeight:170)
						.padding(0)
					}
				}
				.edgesIgnoringSafeArea([.leading, .trailing])
			}
		}
		.navigationTitle((node.user != nil)  ? String(node.user!.longName ?? "Unknown") : "Unknown")
		.navigationBarTitleDisplayMode(.automatic)
		.navigationBarItems(trailing:

			ZStack {

				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
			}
		)
		.onAppear {

			if self.initialLoad{
				
				self.bleManager.context = context
				self.initialLoad = false
			}
		}

	}
}

struct NodeInfoEntityDetail_Previews: PreviewProvider {

	static let bleManager = BLEManager()

	static var previews: some View {
		Group {

			// NodeDetail(node: node)
		}
	}
}
