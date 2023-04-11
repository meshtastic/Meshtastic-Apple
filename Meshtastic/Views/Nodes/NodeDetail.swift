/*
 Abstract:
 A view showing the details for a node.
 */

import SwiftUI
import WeatherKit
import MapKit
import CoreLocation

struct NodeDetail: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.colorScheme) var colorScheme: ColorScheme
	@AppStorage("meshMapType") private var meshMapType = "standard"
	@State private var mapType: MKMapType = .standard
	@State var waypointCoordinate: WaypointCoordinate? 
	@State private var loadedWeather: Bool = false
	@State private var showingDetailsPopover = false
	@State private var showingForecast = false
	@State private var showingShutdownConfirm: Bool = false
	@State private var showingRebootConfirm: Bool = false
	@State private var presentingWaypointForm = false
	@State private var showOverlays: Bool = true
	@State private var customMapOverlay: MapViewSwiftUI.CustomMapOverlay? = MapViewSwiftUI.CustomMapOverlay(
			mapName: "offlinemap",
			tileType: "png",
			canReplaceMapContent: true
		)

	var node: NodeInfoEntity

	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>

	/// The current weather condition for the city.
	@State private var condition: WeatherCondition?
	@State private var temperature: Measurement<UnitTemperature>?
	@State private var humidity: Int?
	@State private var symbolName: String = "cloud.fill"

	@State private var attributionLink: URL?
	@State private var attributionLogo: URL?
	
	
	var body: some View {

		let hwModelString = node.user?.hwModel ?? "UNSET"

		NavigationStack {
			GeometryReader { bounds in
				VStack {
					if node.positions?.count ?? 0 > 0 {
						ZStack {
							let positionArray = node.positions?.array as? [PositionEntity] ?? []
							let lastTenThousand = Array(positionArray.prefix(10000))
							// let todaysPositions = positionArray.filter { $0.time! >= Calendar.current.startOfDay(for: Date()) }
							ZStack {
								MapViewSwiftUI(onLongPress: { coord in
									waypointCoordinate = WaypointCoordinate(id: .init(), coordinate: coord, waypointId: 0)
								}, onWaypointEdit: { wpId in
									if wpId > 0 {
										waypointCoordinate = WaypointCoordinate(id: .init(), coordinate: nil, waypointId: Int64(wpId))
									}
								}, positions: lastTenThousand, waypoints: Array(waypoints),
									mapViewType: mapType,
									userTrackingMode: MKUserTrackingMode.none,
									customMapOverlay: self.customMapOverlay
								)
								VStack(alignment: .leading) {
									Spacer()
									HStack(alignment: .bottom, spacing: 1) {

										Picker("Map Type", selection: $mapType) {
											ForEach(MeshMapType.allCases) { map in
												Text(map.description).tag(map.MKMapTypeValue())
											}
										}
										.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
										.pickerStyle(.menu)
										.padding(5)
										VStack {
											Label(temperature?.formatted(.measurement(width: .narrow)) ?? "??", systemImage: symbolName)
												.font(.caption)

											Label("\(humidity ?? 0)%", systemImage: "humidity")
												.font(.caption2)
										}
										.padding(10)
										.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
										.padding(5)
										#if targetEnvironment(macCatalyst)
										.popover(isPresented: $showingForecast,
												 arrowEdge: .top) {
											Text("Today's Weather Forecast")
												.font(.title)
												.padding()
											let nodeLocation = node.positions?.lastObject as? PositionEntity
											NodeWeatherForecastView(location: CLLocation(latitude: nodeLocation?.nodeCoordinate!.latitude ?? LocationHelper.currentLocation.coordinate.latitude, longitude: nodeLocation?.nodeCoordinate!.longitude ?? LocationHelper.currentLocation.coordinate.longitude) )
												.frame(height: 250)
										}
										#else
										 .sheet(isPresented: $showingForecast) {
											 Text("Today's Weather Forecast")
												 .font(.title)
												 .padding()
											 let nodeLocation = node.positions?.lastObject as? PositionEntity
											 NodeWeatherForecastView(location: CLLocation(latitude: nodeLocation?.nodeCoordinate!.latitude ?? LocationHelper.currentLocation.coordinate.latitude, longitude: nodeLocation?.nodeCoordinate!.longitude ?? LocationHelper.currentLocation.coordinate.longitude) ).frame(height: 250)
												 .presentationDetents([.medium])
												 .presentationDragIndicator(.automatic)
										 }
										#endif
										.gesture(
											LongPressGesture(minimumDuration: 0.5)
												.onEnded { _ in
													showingForecast = true
												}
										)
									}
								}
							}
							.ignoresSafeArea(.all, edges: [.top, .leading, .trailing])
							.frame(idealWidth: bounds.size.width, minHeight: bounds.size.height / 1.65)
						}
					} else {
						HStack {
						}
						.padding([.top], 20)
					}

					ScrollView() {
						NodeInfoView(node: node)
						if self.bleManager.connectedPeripheral != nil && node.metadata != nil {

							HStack {
								let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
								if node.metadata?.canShutdown ?? false {

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
										"are.you.sure",
										isPresented: $showingShutdownConfirm
									) {
										Button("Shutdown Node?", role: .destructive) {
											if !bleManager.sendShutdown(fromUser: connectedNode!.user!, toUser: node.user!, adminIndex: connectedNode!.myInfo!.adminIndex) {
												print("Shutdown Failed")
											}
										}
									}
								}

								Button(action: {
									showingRebootConfirm = true
								}) {
									Label("reboot", systemImage: "arrow.triangle.2.circlepath")
								}
								.buttonStyle(.bordered)
								.buttonBorderShape(.capsule)
								.controlSize(.large)
								.padding()
								.confirmationDialog("are.you.sure",
													isPresented: $showingRebootConfirm
								) {
									Button("reboot.node", role: .destructive) {
										if !bleManager.sendReboot(fromUser: connectedNode!.user!, toUser: node.user!, adminIndex: connectedNode!.myInfo!.adminIndex) {
											print("Reboot Failed")
										}
									}
								}
							}
							.padding(5)
							Divider()
						}
						if node.positions?.count ?? 0 > 0 {
							VStack {
								AsyncImage(url: attributionLogo) { image in
									image
										.resizable()
										.scaledToFit()
								} placeholder: {
									ProgressView()
										.controlSize(.mini)
								}
								.frame(height: 15)

								Link("Other data sources", destination: attributionLink ?? URL(string: "https://weather-data.apple.com/legal-attribution.html")!)
							}
							.font(.footnote)
						}
					}
				}
				.edgesIgnoringSafeArea([.leading, .trailing])
				.sheet(item: $waypointCoordinate, content: { wpc in
					WaypointFormView(coordinate: wpc)
						.presentationDetents([.medium, .large])
						.presentationDragIndicator(.automatic)
				})
				.navigationBarTitle(String(node.user?.longName ?? NSLocalizedString("unknown", comment: "")), displayMode: .inline)
				.navigationBarItems(trailing:
					ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
				})
				.onAppear {
					self.bleManager.context = context
					let currentMapType = MeshMapType(rawValue: meshMapType)
					mapType = currentMapType?.MKMapTypeValue() ?? .standard
				}
				.task(id: node.num) {
					if !loadedWeather {
						do {
							
							if node.positions?.count ?? 0 > 0 {
								
								let mostRecent = node.positions?.lastObject as? PositionEntity
								
								let weather = try await WeatherService.shared.weather(for: mostRecent?.nodeLocation ?? CLLocation(latitude: LocationHelper.currentLocation.coordinate.latitude, longitude: LocationHelper.currentLocation.coordinate.longitude))
								condition = weather.currentWeather.condition
								temperature = weather.currentWeather.temperature
								humidity = Int(weather.currentWeather.humidity * 100)
								symbolName = weather.currentWeather.symbolName
								
								let attribution = try await WeatherService.shared.attribution
								attributionLink = attribution.legalPageURL
								attributionLogo = colorScheme == .light ? attribution.combinedMarkLightURL : attribution.combinedMarkDarkURL
								loadedWeather = true
							}
						} catch {
							print("Could not gather weather information...", error.localizedDescription)
							condition = .clear
							symbolName = "cloud.fill"
						}
					}
				}
			}
		}
	}
}
