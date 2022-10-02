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
	
	@State private var showingDetailsPopover = false
	
	@State var initialLoad: Bool = true
	@State var satsInView = 0
	@State private var showingShutdownConfirm: Bool = false
	@State private var showingRebootConfirm: Bool = false

	var node: NodeInfoEntity

	var body: some View {
		
		let hwModelString = node.user?.hwModel ?? "UNSET"

		NavigationStack {

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
								.frame(idealWidth: bounds.size.width, minHeight: bounds.size.height / 1.70)
							}
						}
						Text("Sats: \(mostRecent.satsInView)").offset( y:-40)
					} else {
						
						HStack {

						}
						.padding([.top], 40)
					}
					
					ScrollView {
						
						Divider()
						
						if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {

							
							HStack {
								
								VStack(alignment: .center) {
									
									Text("AKA").font(.largeTitle)
										.foregroundColor(.gray).fixedSize()
										.offset(y:5)
									CircleText(text: node.user?.shortName ?? "???", color: .accentColor, circleSize: 75, fontSize: 26)
								}
								.padding()

								Divider()

								VStack {

									if node.user != nil {
										
										Image(hwModelString)
											.resizable()
											.aspectRatio(contentMode: .fill)
											.frame(width: 200, height: 200)
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
										
										BatteryGauge(batteryLevel: Double(mostRecent.batteryLevel))
							
										if mostRecent.voltage > 0 {

											Text(String(format: "%.2f", mostRecent.voltage) + " V")
												.font(.title)
												.foregroundColor(.gray)
												.fixedSize()
										}
									}
									.padding()
								}
								
							}
							.padding()
							
							Divider()
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
									
									CircleText(text: node.user?.shortName ?? "???", color: .accentColor)
								}

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

										BatteryGauge(batteryLevel: Double(mostRecent.batteryLevel))
										
										if mostRecent.voltage > 0 {
											
											Text(String(format: "%.2f", mostRecent.voltage) + " V")
												.font(.callout)
												.foregroundColor(.gray)
												.fixedSize()
										}
										
									}
								}
							}
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
							.padding([.bottom], 0)
							Divider()
						}
						
						VStack {
							
							if (node.positions?.count ?? 0) > 0 {
								
								
								
								NavigationLink {
									PositionLog(node: node)
								} label: {
									
									Image(systemName: "building.columns")
										.symbolRenderingMode(.hierarchical)
										.font(.title)
									
									Text("Position Log (\(node.positions?.count ?? 0) Points)")
										.font(.title3)
								}
								.fixedSize(horizontal: false, vertical: true)
								Divider()
							}
							
							if (node.telemetries?.count ?? 0) > 0 {
								
								NavigationLink {
									DeviceMetricsLog(node: node)
								} label: {
									
									Image(systemName: "flipphone")
										.symbolRenderingMode(.hierarchical)
										.font(.title)
									
									Text("Device Metrics Log")
										.font(.title3)
								}
								Divider()
								NavigationLink {
									EnvironmentMetricsLog(node: node)
								} label: {
									
									Image(systemName: "chart.xyaxis.line")
										.symbolRenderingMode(.hierarchical)
										.font(.title)
									
									Text("Environment Metrics Log")
										.font(.title3)
								}
								Divider()
							}
						}
						
						if self.bleManager.connectedPeripheral != nil && self.bleManager.connectedPeripheral.num == node.num && self.bleManager.connectedPeripheral.num == node.num {

							HStack {
								
								if  hwModelString == "TBEAM" || hwModelString == "TECHO" || hwModelString.contains("4631") {
								
									Button(action: {
										
										showingShutdownConfirm = true
									}) {
											
										Label("Power Off", systemImage: "power")
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.large)
									.padding()
									.confirmationDialog(
										"Are you sure?",
										isPresented: $showingShutdownConfirm
									) {
										Button("Shutdown Node?", role: .destructive) {
											
											if !bleManager.sendShutdown(destNum: node.num) {
												
												print("Shutdown Failed")
											}
										}
									}
								}
							
								Button(action: {
									
									showingRebootConfirm = true
									
								}) {
				
									Label("Reboot", systemImage: "arrow.triangle.2.circlepath")
								}
								.buttonStyle(.bordered)
								.buttonBorderShape(.capsule)
								.controlSize(.large)
								.padding()
								.confirmationDialog(
									
									"Are you sure?",
									isPresented: $showingRebootConfirm
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
					}
					.offset( y:-40)
					.padding(.bottom, -40)
				}
				.edgesIgnoringSafeArea([.leading, .trailing])
				.navigationTitle((node.user != nil)  ? String(node.user!.longName ?? "Unknown") : "Unknown")
				.navigationBarTitleDisplayMode(.inline)
				.padding(.bottom, 10)
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
