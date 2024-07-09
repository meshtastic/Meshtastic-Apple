//
//  NodeMapControl.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/9/23.
//
import SwiftUI
import CoreLocation
import MapKit
import WeatherKit
import OSLog

struct NodeMapMapkit: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	/// Weather
	/// The current weather condition for the city.
	@State private var condition: WeatherCondition?
	@State private var temperature: Measurement<UnitTemperature>?
	@State private var humidity: Int?
	@State private var symbolName: String = "cloud.fill"
	@State private var attributionLink: URL?
	@State private var attributionLogo: URL?

	@Environment(\.colorScheme) var colorScheme: ColorScheme
	@AppStorage("meshMapType") private var meshMapType = 0
	@AppStorage("meshMapShowNodeHistory") private var meshMapShowNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var meshMapShowRouteLines = false
	@State private var selectedMapLayer: MapLayer = .standard
	@State var waypointCoordinate: WaypointCoordinate?
	@State var editingWaypoint: Int = 0
	@State private var customMapOverlay: MapViewSwiftUI.CustomMapOverlay? = MapViewSwiftUI.CustomMapOverlay(
		mapName: "offlinemap",
		tileType: "png",
		canReplaceMapContent: true
	)
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>
	@ObservedObject var node: NodeInfoEntity

	var body: some View {

		NavigationStack {
			GeometryReader { bounds in
				VStack {
					if node.hasPositions {
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
									},
									selectedMapLayer: selectedMapLayer,
									positions: lastTenThousand,
									waypoints: Array(waypoints),
									userTrackingMode: MKUserTrackingMode.none,
									showNodeHistory: meshMapShowNodeHistory,
									showRouteLines: meshMapShowRouteLines,
									customMapOverlay: self.customMapOverlay
								)
								VStack(alignment: .leading) {
									Spacer()
									HStack(alignment: .bottom, spacing: 1) {
										Picker("Map Type", selection: $selectedMapLayer) {
											ForEach(MapLayer.allCases, id: \.self) { layer in
												if layer == MapLayer.offline && UserDefaults.enableOfflineMaps {
													Text(layer.localized)
												} else if layer != MapLayer.offline {
													Text(layer.localized)
												}
											}
										}
										.onChange(of: (selectedMapLayer)) { newMapLayer in
											UserDefaults.mapLayer = newMapLayer
										}
										.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
										.pickerStyle(.menu)
										.padding(5)
										//if UserDefaults.environmentEnableWeatherKit {
											//VStack {
												LocalWeatherConditions(location: node.latestPosition?.nodeLocation)
											//}
										//}
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
				}
				.edgesIgnoringSafeArea([.leading, .trailing])
				.sheet(item: $waypointCoordinate, content: { wpc in
					WaypointFormMapKit(coordinate: wpc)
						.presentationDetents([.medium, .large])
						.presentationDragIndicator(.automatic)
				})
				.navigationBarTitle(String(node.user?.longName ?? "unknown".localized), displayMode: .inline)
				.navigationBarItems(trailing:
					ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
				})
			}
			.padding(.bottom, 2)
		}
	}
}
