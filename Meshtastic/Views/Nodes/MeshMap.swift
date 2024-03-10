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
	@AppStorage("mapLayer") private var selectedMapLayer: MapLayer = .hybrid
	// Map Configuration
	@Namespace var mapScope
	@State var mapStyle: MapStyle = MapStyle.standard(elevation: .realistic, emphasis: MapStyle.StandardEmphasis.muted ,pointsOfInterest: .all, showsTraffic: true)
	@State var position = MapCameraPosition.automatic
	@State var scene: MKLookAroundScene?
	@State var isLookingAround = false
	@State var isEditingSettings = false
	@State var selectedPosition: PositionEntity?
	@State var showWaypoints = true
	@State var editingWaypoint: WaypointEntity?
	@State var selectedWaypoint: WaypointEntity?
	@State var newWaypointCoord :CLLocationCoordinate2D?
	@State var isMeshMap = true
	
	var delay: Double = 0
	@State private var scale: CGFloat = 0.5
	/// && time >= %@
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "time", ascending: true)],
				  predicate: NSPredicate(format: "nodePosition != nil && latest == true", Calendar.current.date(byAdding: .day, value: -7, to: Date())! as NSDate), animation: .none)
	private var positions: FetchedResults<PositionEntity>
	
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>
	
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
				  predicate: NSPredicate(format: "enabled == true", ""), animation: .none)
	private var routes: FetchedResults<RouteEntity>

	var body: some View {
		
		let lineCoords = Array(positions).compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationHelper.DefaultLocation
		})
		NavigationStack {
			ZStack {
				MapReader { reader in
					Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity), scope: mapScope) {
						/// Convex Hull
						if showConvexHull {
							if lineCoords.count > 0 {
								let hull = lineCoords.getConvexHull()
								MapPolygon(coordinates: hull)
									.stroke(.blue, lineWidth: 3)
									.foregroundStyle(.indigo.opacity(0.4))
							}
						}
						/// Position Annotations
						ForEach(Array(positions), id: \.id) { position in
							/// Node color from node.num
							let nodeColor = UIColor(hex: UInt32(position.nodePosition?.num ?? 0))
							Annotation(position.nodePosition?.user?.longName ?? "?", coordinate: position.coordinate) {
								LazyVStack {
									ZStack {
										let nodeColor = UIColor(hex: UInt32(position.nodePosition?.num ?? 0))
										if position.nodePosition?.isOnline ?? false {
											Circle()
												.fill(Color(nodeColor.lighter()).opacity(0.4).shadow(.drop(color: Color(nodeColor).isLight() ? .black : .white, radius: 5)))
												.foregroundStyle(Color(nodeColor.lighter()).opacity(0.3))
												.scaleEffect(scale)
												.animation(
													Animation.easeInOut(duration: 0.6)
														.repeatForever().delay(delay), value: scale
												)
												.onAppear {
													self.scale = 1
												}
												.frame(width: 60, height: 60)
										}
										if position.nodePosition?.hasDetectionSensorMetrics ?? false {
											Image(systemName: "sensor.fill")
												.symbolRenderingMode(.palette)
												.symbolEffect(.variableColor)
												.padding()
												.foregroundStyle(.white)
												.background(Color(nodeColor))
												.clipShape(Circle())
										} else {
											CircleText(text: position.nodePosition?.user?.shortName ?? "?", color: Color(nodeColor), circleSize: 40)
										}
									}
								}
								.onTapGesture { location in
									selectedPosition = (selectedPosition == position ? nil : position)
								}
							}
							/// Reduced Precision Map Circles
							if 11...16 ~= position.precisionBits {
								let pp = PositionPrecision(rawValue: Int(position.precisionBits))
								let radius : CLLocationDistance = pp?.precisionMeters ?? 0
								if radius > 0.0 {
									MapCircle(center: position.coordinate, radius: radius)
										.foregroundStyle(Color(nodeColor).opacity(0.25))
										.stroke(.white, lineWidth: 2)
								}
							}
							/// Routes
							ForEach(Array(routes), id: \.id) { route in
								let routeLocations = Array(route.locations!) as! [LocationEntity]
								let routeCoords = routeLocations.compactMap({(loc) -> CLLocationCoordinate2D in
									return loc.locationCoordinate ?? LocationHelper.DefaultLocation
								})
								Annotation("Start", coordinate: routeCoords.first ?? LocationHelper.DefaultLocation) {
									ZStack {
										Circle()
											.fill(Color(.green))
											.strokeBorder(.white, lineWidth: 3)
											.frame(width: 15, height: 15)
									}
								}
								.annotationTitles(.automatic)
								Annotation("Finish", coordinate: routeCoords.last ?? LocationHelper.DefaultLocation) {
									ZStack {
										Circle()
											.fill(Color(.black))
											.strokeBorder(.white, lineWidth: 3)
											.frame(width: 15, height: 15)
									}
								}
								.annotationTitles(.automatic)
								let solid = StrokeStyle(
									lineWidth: 3,
									lineCap: .round, lineJoin: .round
								)
								MapPolyline(coordinates: routeCoords)
									.stroke(Color(UIColor(hex: UInt32(route.color))), style: solid)
								
							}
						}
						
						/// Waypoint Annotations
						if waypoints.count > 0 && showWaypoints {
							ForEach(Array(waypoints), id: \.id) { waypoint in
								Annotation(waypoint.name ?? "?", coordinate: waypoint.coordinate) {
									LazyVStack {
										CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 40)
											.onTapGesture(perform: { location in
												selectedWaypoint = (selectedWaypoint == waypoint ? nil : waypoint)
											})
									}
								}
							}
						}
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
					.onTapGesture(count: 1, perform: { location in
						newWaypointCoord = reader.convert(location , from: .local)
					})
					.onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10) {
						editingWaypoint = WaypointEntity(context: context)
						editingWaypoint!.name = "Waypoint Pin"
						editingWaypoint!.expire = Date.now.addingTimeInterval(60 * 480)
						editingWaypoint!.latitudeI = Int32((newWaypointCoord?.latitude ?? 0) * 1e7)
						editingWaypoint!.longitudeI = Int32((newWaypointCoord?.longitude ?? 0) * 1e7)
						editingWaypoint!.expire = Date.now.addingTimeInterval(60 * 480)
						editingWaypoint!.id = 0
					}
					
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
					/// Look Around Button
					if self.scene != nil {
						Button(action: {
							withAnimation {
								isLookingAround = !isLookingAround
							}
						}) {
							Image(systemName: isLookingAround ? "binoculars.fill" : "binoculars")
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
		.navigationTitle("Mesh Map")
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
