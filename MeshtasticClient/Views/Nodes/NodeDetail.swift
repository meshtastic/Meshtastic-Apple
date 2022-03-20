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
	@EnvironmentObject var userSettings: UserSettings

	var node: NodeInfoEntity

	var body: some View {

		HStack {

			GeometryReader { bounds in

				VStack {

					if node.positions?.count ?? 0 >= 1 {

						let mostRecent = node.positions?.lastObject as! PositionEntity

						if mostRecent.coordinate != nil {

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
									   CircleText(text: node.user!.shortName ?? "???", color: .accentColor, circleSize: 32, fontSize: 14)
								   }
								)
							}
							.frame(idealWidth: bounds.size.width, maxHeight: bounds.size.height / 3)
						} else {

							Image(node.user?.hwModel ?? "UNSET")
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(width: bounds.size.width, height: bounds.size.height / 2)
						}
					} else {

						Image(node.user?.hwModel ?? "UNSET")
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(width: bounds.size.width, height: bounds.size.height / 2)
					}

					ScrollView {

						if node.lastHeard != nil {

							HStack {

								Image(systemName: "clock.badge.checkmark.fill")
									.font(.title)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
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

							if node.positions?.count ?? 0 >= 1 {

								let mostRecent = node.positions?.lastObject as! PositionEntity

								Divider()

								VStack(alignment: .center) {

									BatteryIcon(batteryLevel: mostRecent.batteryLevel, font: .title, color: .accentColor)
										.padding(.bottom)
									if mostRecent.batteryLevel > 0 {

										Text("Battery")
											.font(.title2)
											.fixedSize()
											.textCase(.uppercase)
										Text(String(mostRecent.batteryLevel) + "%")
											.font(.title2)
											.foregroundColor(.gray)
											.symbolRenderingMode(.hierarchical)
									} else {

										Text("Powered")
											.font(.callout)
											.fixedSize()
											.textCase(.uppercase)
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
						.padding()

						if node.positions?.count ?? 0 >= 1 {

							Divider()

							HStack {

								Image(systemName: "location.circle.fill")
									.font(.title)
									.foregroundColor(.accentColor)
									.symbolRenderingMode(.hierarchical)
								Text("Location History").font(.title2)
							}
							.padding()

							Divider()

							ForEach(node.positions!.array as! [PositionEntity], id: \.self) { (mappin: PositionEntity) in

								if mappin.coordinate != nil {

									VStack {

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
											Text("\(mappin.time!, style: .date) \(mappin.time!, style: .time)")
												.foregroundColor(.gray)
												.font(.caption)
											Divider()

											HStack {
												
												BatteryIcon(batteryLevel: mappin.batteryLevel, font: .subheadline, color: .accentColor)
												
												if mappin.batteryLevel > 0 {
													
													Text(String(mappin.batteryLevel) + "%")
														.font(.caption2)
														.foregroundColor(.gray)
												}
											}
										}
									}
									.padding(1)
									Divider()
								}
							}
						}
					}
				}
				.edgesIgnoringSafeArea([.leading, .trailing])
				.padding(1)
			}
		}
		.navigationTitle((node.user != nil)  ? String(node.user!.longName ?? "Unknown") : "Unknown")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(trailing:

			ZStack {

				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "???")
			}
		)
		.onAppear(perform: {

			self.bleManager.context = context
			self.bleManager.userSettings = userSettings

		})
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
