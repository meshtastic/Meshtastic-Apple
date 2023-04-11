//
//  NodeMap.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 8/7/21.
//

import SwiftUI
import MapKit
import CoreLocation
import CoreData

// A simple struct with waypoint data
struct WaypointCoordinate: Identifiable {

	let id: UUID
	let coordinate: CLLocationCoordinate2D?
	let waypointId: Int64
}

struct NodeMap: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings

	@AppStorage("meshMapCustomTileServer") var customTileServer: String = "" {
		didSet {
			if customTileServer == "" {
				self.customMapOverlay = nil
			} else {
				self.customMapOverlay = MapViewSwiftUI.CustomMapOverlay(
					mapName: customTileServer,
					tileType: "png",
					canReplaceMapContent: true
				)
			}
		}
	}
	@AppStorage("meshMapType") private var meshMapType = "standard"
	@AppStorage("meshMapUserTrackingMode") private var meshMapUserTrackingMode = 0

	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "time", ascending: true)],
				  predicate: NSPredicate(format: "time >= %@ && nodePosition != nil", Calendar.current.startOfDay(for: Date()) as NSDate), animation: .none)
	private var positions: FetchedResults<PositionEntity>

	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>

	@State private var mapType: MKMapType = .standard
	@State private var userTrackingMode: MKUserTrackingMode = .none
	@State var waypointCoordinate: WaypointCoordinate?
	@State private var customMapOverlay: MapViewSwiftUI.CustomMapOverlay? = MapViewSwiftUI.CustomMapOverlay(
			mapName: "offlinemap",
			tileType: "png",
			canReplaceMapContent: true
		)

	var body: some View {

		NavigationStack {
			ZStack {

				MapViewSwiftUI(
					onLongPress: { coord in
						waypointCoordinate = WaypointCoordinate(id: .init(), coordinate: coord, waypointId: 0)
				}, onWaypointEdit: { wpId in
					if wpId > 0 {
						waypointCoordinate = WaypointCoordinate(id: .init(), coordinate: nil, waypointId: Int64(wpId))
					}
				}, positions: Array(positions),
				   waypoints: Array(waypoints),
				   mapViewType: mapType,
				   userTrackingMode: userTrackingMode,
				   customMapOverlay: self.customMapOverlay
				)
				VStack {
					Spacer()
					Picker("Map Type", selection: $mapType) {
						ForEach(MeshMapType.allCases) { map in
							Text(map.description).tag(map.MKMapTypeValue())
						}
					}
					.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.pickerStyle(.menu)
					.padding(.bottom, 5)
				}
			}
			.ignoresSafeArea(.all, edges: [.top, .leading, .trailing])
			.frame(maxHeight: .infinity)
			.sheet(item: $waypointCoordinate, content: { wpc in
				WaypointFormView(coordinate: wpc)
					.presentationDetents([.medium, .large])
					.presentationDragIndicator(.automatic)
			})
		}
		.navigationBarItems(leading:
								MeshtasticLogo(), trailing:
								ZStack {
			ConnectedDevice(
				bluetoothOn: bleManager.isSwitchedOn,
				deviceConnected: bleManager.connectedPeripheral != nil,
				name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName :
					"????")
		})
		.onAppear(perform: {
			UIApplication.shared.isIdleTimerDisabled = true
			self.bleManager.context = context
			self.bleManager.userSettings = userSettings
			userTrackingMode = UserTrackingModes(rawValue: meshMapUserTrackingMode)?.MKUserTrackingModeValue() ?? MKUserTrackingMode.none
			let currentMapType = MeshMapType(rawValue: meshMapType)
			mapType = currentMapType?.MKMapTypeValue() ?? .standard
		})
		.onDisappear(perform: {
			UIApplication.shared.isIdleTimerDisabled = false
		})
    }
}
