//
//  MeshMap.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/23.
//

import SwiftUI
import CoreData
import CoreLocation
import Foundation
#if canImport(MapKit)
import MapKit
#endif



@available(iOS 17.0, macOS 14.0, *)
struct MeshMap: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@StateObject var appState = AppState.shared
	/// Parameters
	@State var showUserLocation: Bool = true
	/// Map State User Defaults
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
	@AppStorage("enableMapConvexHull") private var showConvexHull = false
	@AppStorage("enableMapTraffic") private var showTraffic: Bool = false
	@AppStorage("enableMapPointsOfInterest") private var showPointsOfInterest: Bool = false
	@AppStorage("mapLayer") private var selectedMapLayer: MapLayer = .standard
	// Map Configuration
	@Namespace var mapScope
	@State var mapStyle: MapStyle = MapStyle.standard(elevation: .flat, emphasis: MapStyle.StandardEmphasis.muted ,pointsOfInterest: .all, showsTraffic: true)
	@State var position = MapCameraPosition.camera(MapCamera(centerCoordinate: LocationHelper.currentLocation, distance: 2500000, heading: 0, pitch: 0))
	@State var isEditingSettings = false
	@State var selectedPosition: PositionEntity?
	@State var showWaypoints = false
	@State var editingWaypoint: WaypointEntity?
	@State var selectedWaypoint: WaypointEntity?
	@State var newWaypointCoord: CLLocationCoordinate2D?
	@State var isMeshMap = true
	
	@FetchRequest(fetchRequest: PositionEntity.allPositionsFetchRequest(), animation: .none)
	var positions: FetchedResults<PositionEntity>
	
	@FetchRequest(fetchRequest: WaypointEntity.allWaypointssFetchRequest(), animation: .none)
	var waypoints: FetchedResults<WaypointEntity>
	
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
				  predicate: NSPredicate(format: "enabled == true", ""), animation: .none)
	private var routes: FetchedResults<RouteEntity>

	var body: some View {
		
		NavigationStack {
			ZStack {
				MapReader { reader in
					Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity), scope: mapScope) {
						MeshMapContent(positions: Array(positions), waypoints: Array(waypoints), routes: Array(routes), showUserLocation: $showUserLocation, showNodeHistory: $showNodeHistory, showRouteLines: $showRouteLines, showConvexHull: $showConvexHull, showTraffic: $showTraffic, showPointsOfInterest: $showPointsOfInterest, selectedMapLayer: $selectedMapLayer, selectedPosition: $selectedPosition, showWaypoints: $showWaypoints, selectedWaypoint: $selectedWaypoint)
				
					}
					.mapScope(mapScope)
					.mapStyle(mapStyle)
					.mapControls {
						MapScaleView(scope: mapScope)
							.mapControlVisibility(.automatic)
						MapPitchToggle(scope: mapScope)
							.mapControlVisibility(.automatic)
						MapCompass(scope: mapScope)
							.mapControlVisibility(.automatic)
					}
					.controlSize(.regular)

					.onTapGesture(count: 1,  perform: { position in
							print(position)
							newWaypointCoord = reader.convert(position, from: .local) ??  CLLocationCoordinate2D.init()
					})
					.gesture(
						LongPressGesture(minimumDuration: 0.5)
							.sequenced(before: SpatialTapGesture(coordinateSpace: .local))
							.onEnded { value in
							switch value {
								case let .second(_, tapValue):
									guard let point = tapValue?.location else {
										print("Unable to retreive tap location from gesture data.")
										return
									}
									
									guard let coordinate = reader.convert(point, from: .local) else {
										print("Unable to convert local point to coordinate on map.")
										return
									}

									newWaypointCoord = coordinate
									editingWaypoint = WaypointEntity(context: context)
									editingWaypoint!.name = "Waypoint Pin"
									editingWaypoint!.expire = Date.now.addingTimeInterval(60 * 480)
									editingWaypoint!.latitudeI = Int32((newWaypointCoord?.latitude ?? 0) * 1e7)
									editingWaypoint!.longitudeI = Int32((newWaypointCoord?.longitude ?? 0) * 1e7)
									editingWaypoint!.expire = Date.now.addingTimeInterval(60 * 480)
									editingWaypoint!.id = 0
									print("Long press occured at: \(coordinate)")
								default: return
							}
					})
				}
			}
			.sheet(item: $selectedPosition) { selection in
				PositionPopover(position: selection, popover: false)
					.padding()
			}
			.sheet(item: $selectedWaypoint) { selection in
				WaypointForm(waypoint: selection)
					.padding()
			}
			.sheet(item: $editingWaypoint) { selection in
				WaypointForm(waypoint: selection, editMode: true)
					.padding()
			}
			.sheet(isPresented: $isEditingSettings) {
				MapSettingsForm(nodeHistory: $showNodeHistory, routeLines: $showRouteLines, convexHull: $showConvexHull, traffic: $showTraffic, pointsOfInterest: $showPointsOfInterest, mapLayer: $selectedMapLayer, meshMap: $isMeshMap)
			}
			.onChange(of: (appState.navigationPath)) { newPath in
				
				if ((newPath?.hasPrefix("meshtastic://open-waypoint")) != nil) {
					guard let url = URL(string: appState.navigationPath ?? "NONE") else {
						print("Invalid URL")
						return
					}
					guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
					  print("Invalid URL Components")
					  return
					}
					guard let action = components.host, action == "open-waypoint" else {
					  print("Unknown waypoint URL action")
					  return
					}
					guard let waypointId = components.queryItems?.first(where: { $0.name == "id" })?.value else {
					  print("Waypoint id not found")
					  return
					}
					guard let waypoint = waypoints.first(where: { $0.id == Int64(waypointId) }) else {
					  print("Waypoint not found")
					  return
					}
					showWaypoints = true
					position = .camera(MapCamera(centerCoordinate: waypoint.coordinate, distance: 1000, heading: 0, pitch: 60))
				}
			}
			.onChange(of: (selectedMapLayer)) { newMapLayer in
				switch selectedMapLayer {
				case .standard:
					UserDefaults.mapLayer = newMapLayer
					mapStyle = MapStyle.standard(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
				case .hybrid:
					UserDefaults.mapLayer = newMapLayer
					mapStyle = MapStyle.hybrid(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
				case .satellite:
					UserDefaults.mapLayer = newMapLayer
					mapStyle = MapStyle.imagery(elevation: .realistic)
				case .offline:
					return
				}
			}
			.safeAreaInset(edge: .bottom, alignment: UIDevice.current.userInterfaceIdiom == .phone ? .leading : .trailing) {
				HStack {
					Button(action: {
						withAnimation {
							isEditingSettings = !isEditingSettings
						}
					}) {
						Image(systemName: isEditingSettings ? "info.circle.fill" : "info.circle")
							.padding(.vertical, 5)
					}
					.tint(Color(UIColor.secondarySystemBackground))
					.foregroundColor(.accentColor)
					.buttonStyle(.borderedProminent)
					/// Show / Hide Waypoints Button
					if waypoints.count > 0 {
						
						Button(action: {
							withAnimation {
								showWaypoints = !showWaypoints
							}
						}) {
						Image(systemName: showWaypoints ? "signpost.right.and.left.fill" : "signpost.right.and.left")
							.padding(.vertical, 5)
						}
						.tint(Color(UIColor.secondarySystemBackground))
						.foregroundColor(.accentColor)
						.buttonStyle(.borderedProminent)
					}
				}
				.controlSize(.regular)
				.padding(5)
			}
		}
		.navigationTitle("\(positions.count) Nodes")
		.navigationBarItems(leading: MeshtasticLogo(), trailing: ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			UIApplication.shared.isIdleTimerDisabled = true
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			switch selectedMapLayer {
			case .standard:
				mapStyle = MapStyle.standard(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
			case .hybrid:
				mapStyle = MapStyle.hybrid(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
			case .satellite:
				mapStyle = MapStyle.imagery(elevation: .realistic)
			case .offline:
				mapStyle = MapStyle.hybrid(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
			}
		}
		.onDisappear(perform: {
			UIApplication.shared.isIdleTimerDisabled = false
		})
	}
}
