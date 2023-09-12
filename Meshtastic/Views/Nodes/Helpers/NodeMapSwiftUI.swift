//
//  NodeMapSwiftUI.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/11/23.
//

import SwiftUI
import CoreLocation
import MapKit
import WeatherKit

@available(iOS 17.0, *)
struct NodeMapSwiftUI: View {
	
	@Namespace var mapScope
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@AppStorage("meshMapType") private var meshMapType = 0
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
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
		let positionArray = node.positions?.array as? [PositionEntity] ?? []
		let mostRecent = node.positions?.lastObject as? PositionEntity
		if mostRecent != nil {
			NavigationStack {
				ZStack {
					
					Map(initialPosition: .camera(MapCamera(centerCoordinate: mostRecent!.coordinate, distance: 500, heading: 90, pitch: 60)),
						bounds: MapCameraBounds(minimumDistance: 100, maximumDistance: 3500),
						scope: mapScope) {
							ForEach(positionArray, id: \.id) { position in
								Annotation(position.latest ? node.user?.shortName ?? "?" : "", coordinate:  position.coordinate) {
									ZStack {
										if position.latest {
											Circle()
												.foregroundStyle(Color(UIColor(hex: UInt32(node.num)).darker()).opacity(0.4))
												.frame(width: 60, height: 60)
											Image(systemName: "flipphone")
												.symbolEffect(.pulse.byLayer)
												.padding(7)
												.foregroundStyle(Color(UIColor(hex: UInt32(node.num)).lighter()).isLight() ? .black : .white)
												.background(Color(UIColor(hex: UInt32(node.num)).darker()))
												.clipShape(Circle())
										} else {
											if showNodeHistory {
												Image(systemName: "mappin.circle")
													.padding(2)
													.foregroundStyle(Color(UIColor(hex: UInt32(node.num)).lighter()).isLight() ? .black : .white)
													.background(Color(UIColor(hex: UInt32(node.num)).lighter()))
													.clipShape(Circle())
											}
										}
										
									}
								}
								.tag(node.num)
								
//								Marker(node.user?.shortName ?? "?", systemImage: "mappin.and.ellipse", coordinate: position.coordinate)
//									.tint(position.latest ? Color(UIColor(hex: UInt32(node.num)).darker()) : Color(UIColor(hex: UInt32(node.num)).lighter()))
//									.tag(node.num)
							}
						}
						.mapScope(mapScope)
						.mapStyle(.imagery(elevation: .realistic))
						.mapControls {
							MapScaleView(scope: mapScope)
								.mapControlVisibility(.visible)
							MapUserLocationButton(scope: mapScope)
								.mapControlVisibility(.visible)
							MapPitchToggle(scope: mapScope)
								.mapControlVisibility(.visible)
						#if targetEnvironment(macCatalyst)
							MapZoomStepper(scope: mapScope)
								.mapControlVisibility(.visible)
							MapPitchSlider(scope: mapScope)
								.mapControlVisibility(.visible)
						#endif
							MapCompass(scope: mapScope)
								.mapControlVisibility(.visible)
						}
						.controlSize(.large)
				}
				.navigationBarTitle(String("Node Map " + (node.user?.shortName ?? "unknown".localized)), displayMode: .inline)
				.navigationBarItems(trailing:
					ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
				})
			}
		}
	}
}
