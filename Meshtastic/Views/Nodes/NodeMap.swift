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
	@AppStorage("meshMapType") private var meshMapType = "hybridFlyover"
	
	//&& nodePosition != nil
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "time", ascending: true)],
				  predicate: NSPredicate(format: "time >= %@ && nodePosition != nil", Calendar.current.startOfDay(for: Date()) as NSDate), animation: .none)
	private var positions: FetchedResults<PositionEntity>
	
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>
	
	@State private var mapType: MKMapType = .standard
	@State var waypointCoordinate: CLLocationCoordinate2D = LocationHelper.DefaultLocation
	@State var editingWaypoint: Int = 0
	@State private var presentingWaypointForm = false
	@State private var customMapOverlay: MapViewSwiftUI.CustomMapOverlay? = MapViewSwiftUI.CustomMapOverlay(
			mapName: "offlinemap",
			tileType: "png",
			canReplaceMapContent: true
		)
	@State private var overlays: [MapViewSwiftUI.Overlay] = []
	
    var body: some View {

        NavigationStack {
			ZStack {
				
				MapViewSwiftUI(onLongPress: { coord in
					waypointCoordinate = coord
					editingWaypoint = 0
					if waypointCoordinate.distance(from: LocationHelper.DefaultLocation) == 0.0 {
						print("Apple Park")
					} else {
						presentingWaypointForm = true
					}
				}, onWaypointEdit: { wpId in
					if wpId > 0 {
						editingWaypoint = wpId
						presentingWaypointForm = true
					}
				}, positions: Array(positions),
					waypoints: Array(waypoints),
					mapViewType: mapType ,
					centerOnPositionsOnly: false,
					customMapOverlay: self.customMapOverlay,
					overlays: self.overlays
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
			.sheet(isPresented: $presentingWaypointForm ) {//,  onDismiss: didDismissSheet) {
				WaypointFormView(coordinate: waypointCoordinate, waypointId: editingWaypoint)
					.presentationDetents([.medium, .large])
					.presentationDragIndicator(.automatic)
				
			}
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
			self.bleManager.context = context
			self.bleManager.userSettings = userSettings
			
			switch meshMapType {
				case "standard":
					mapType = .standard
					break
				case "mutedStandard":
					mapType = .mutedStandard
					break
				case "hybrid":
					mapType = .hybrid
					break
				case "hybridFlyover":
					mapType = .hybridFlyover
					break
				case "satellite":
					mapType = .satellite
					break
				case "satelliteFlyover":
					mapType = .satelliteFlyover
					break
				default:
					mapType = .hybridFlyover
			}
		})
    }
}
