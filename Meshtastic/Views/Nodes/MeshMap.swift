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
import OSLog
#if canImport(MapKit)
import MapKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct MeshMap: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@ObservedObject
	var router: Router

	/// Parameters
	@State var showUserLocation: Bool = true
	/// Map State User Defaults
	@AppStorage("enableMapTraffic") private var showTraffic: Bool = false
	@AppStorage("enableMapPointsOfInterest") private var showPointsOfInterest: Bool = false
	@AppStorage("mapLayer") private var selectedMapLayer: MapLayer = .standard
	// Map Configuration
	@Namespace var mapScope
	@State var mapStyle: MapStyle = MapStyle.standard(elevation: .flat, emphasis: MapStyle.StandardEmphasis.muted, pointsOfInterest: .excludingAll, showsTraffic: false)
	@State var position = MapCameraPosition.automatic
	@State private var distance = 10000.0
	@State private var editingSettings = false
	@State private var editingFilters = false
	@State var selectedPosition: PositionEntity?
	@State var editingWaypoint: WaypointEntity?
	@State var selectedWaypoint: WaypointEntity?
	@State var selectedWaypointId: String?
	@State var newWaypointCoord: CLLocationCoordinate2D?
	@State var isMeshMap = true
	/// Filter
	@State private var searchText = ""
	@State private var viaLora = true
	@State private var viaMqtt = true
	@State private var isOnline = false
	@State private var isPkiEncrypted = false
	@State private var isFavorite = false
	@State private var isEnvironment = false
	@State private var distanceFilter = false
	@State private var maxDistance: Double = 800000
	@State private var hopsAway: Double = -1.0
	@State private var roleFilter = false
	@State private var deviceRoles: Set<Int> = []

	var body: some View {

		NavigationStack {
			ZStack {
				MapReader { reader in
					Map(
						position: $position,
						bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity),
						scope: mapScope
					) {
						MeshMapContent(
							showUserLocation: $showUserLocation,
							showTraffic: $showTraffic,
							showPointsOfInterest: $showPointsOfInterest,
							selectedMapLayer: $selectedMapLayer,
							selectedPosition: $selectedPosition,
							selectedWaypoint: $selectedWaypoint
						)
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
					.onMapCameraChange(frequency: MapCameraUpdateFrequency.continuous, { context in
						distance = context.camera.distance
					})
					.onTapGesture(count: 1, perform: { position in
						newWaypointCoord = reader.convert(position, from: .local) ??  CLLocationCoordinate2D.init()
					})
					.gesture(
						LongPressGesture(minimumDuration: 0.5)
							.sequenced(before: SpatialTapGesture(coordinateSpace: .local))
							.onEnded { value in
							switch value {
							case let .second(_, tapValue):
								guard let point = tapValue?.location else {
									Logger.services.error("Unable to retreive tap location from gesture data.")
									return
								}

								guard let coordinate = reader.convert(point, from: .local) else {
									Logger.services.error("Unable to convert local point to coordinate on map.")
									return
								}
								centerMapAt(coordinate: coordinate)

								newWaypointCoord = coordinate
								editingWaypoint = WaypointEntity(context: context)
								editingWaypoint!.name = "Waypoint Pin"
								editingWaypoint!.expire = Date.now.addingTimeInterval(60 * 480)
								editingWaypoint!.latitudeI = Int32((newWaypointCoord?.latitude ?? 0) * 1e7)
								editingWaypoint!.longitudeI = Int32((newWaypointCoord?.longitude ?? 0) * 1e7)
								editingWaypoint!.expire = Date.now.addingTimeInterval(60 * 480)
								editingWaypoint!.id = 0
								Logger.services.debug("Long press occured at Lat: \(coordinate.latitude) Long: \(coordinate.longitude)")
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
			.sheet(isPresented: $editingSettings) {
				MapSettingsForm(traffic: $showTraffic, pointsOfInterest: $showPointsOfInterest, mapLayer: $selectedMapLayer, meshMap: $isMeshMap)
			}
			.onChange(of: router.navigationState) {
				guard case .map = router.navigationState.selectedTab else { return }
				// TODO: handle deep link for waypoints
			}
			.onChange(of: selectedMapLayer) { newMapLayer in
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
			.sheet(isPresented: $editingFilters) {
				NodeListFilter(
					viaLora: $viaLora,
					viaMqtt: $viaMqtt,
					isOnline: $isOnline,
					isPkiEncrypted: $isPkiEncrypted,
					isFavorite: $isFavorite,
					isEnvironment: $isEnvironment,
					distanceFilter: $distanceFilter,
					maximumDistance: $maxDistance,
					hopsAway: $hopsAway,
					roleFilter: $roleFilter,
					deviceRoles: $deviceRoles
				)
			}
			.safeAreaInset(edge: .bottom, alignment: .trailing) {
				HStack {
					Spacer()
					Button(action: {
						withAnimation {
							editingSettings = !editingSettings
						}
					}) {
						Image(systemName: editingSettings ? "info.circle.fill" : "info.circle")
							.padding(.vertical, 5)
					}
					.tint(Color(UIColor.secondarySystemBackground))
					.foregroundColor(.accentColor)
					.buttonStyle(.borderedProminent)
//					Button(action: {
//						withAnimation {
//							editingFilters = !editingFilters
//						}
//					}) {
//						Image(systemName: !editingFilters ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
//							.padding(.vertical, 5)
//					}
//					.tint(Color(UIColor.secondarySystemBackground))
//					.foregroundColor(.accentColor)
//					.buttonStyle(.borderedProminent)
				}
				.controlSize(.regular)
				.padding(5)
			}
		}
		.navigationBarItems(leading: MeshtasticLogo(), trailing: ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			UIApplication.shared.isIdleTimerDisabled = true

			//	let wayPointEntity = getWaypoint(id: Int64(deepLinkManager.waypointId) ?? -1, context: context)
			// if wayPointEntity.id > 0 {
			//	position = .camera(MapCamera(centerCoordinate: wayPointEntity.coordinate, distance: 1000, heading: 0, pitch: 60))
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

	// moves the map to a new coordinate
	private func centerMapAt(coordinate: CLLocationCoordinate2D) {
		withAnimation(.easeInOut(duration: 0.2), {
			position = .camera(
				MapCamera(
					centerCoordinate: coordinate, // Set new center
					distance: distance,           // Preserve current zoom distance
					heading: 0,      			  // align north
					pitch: 0                      // set view to top down
				)
			)
		})
	}
}
