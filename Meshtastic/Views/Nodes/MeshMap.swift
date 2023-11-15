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
	
	var delay: Double = 0
	@State private var scale: CGFloat = 0.5
	
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "time", ascending: true)],
				  predicate: NSPredicate(format: "time >= %@ && nodePosition != nil && latest == true", Calendar.current.date(byAdding: .day, value: -30, to: Date())! as NSDate), animation: .none)
	private var positions: FetchedResults<PositionEntity>
	
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>

	var body: some View {
		
		let lineCoords = Array(positions).compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationHelper.DefaultLocation
		})
		NavigationStack {
			ZStack {
				MapReader { reader in
					
					Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity), scope: mapScope) {
						/// Waypoint Annotations
						if waypoints.count > 0 && showWaypoints {
							ForEach(Array(waypoints), id: \.id) { waypoint in
								Annotation(waypoint.name ?? "?", coordinate: waypoint.coordinate) {
									ZStack {
										CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 40)
											.onTapGesture(perform: { location in
												let pinLocation = reader.convert(location, from: .local)
												selectedWaypoint = (selectedWaypoint == waypoint ? nil : waypoint)
											})
									}
								}
							}
						}
						/// Convex Hull
						if showConvexHull {
							let hull = lineCoords.getConvexHull()
							MapPolygon(coordinates: hull)
								.stroke(.blue, lineWidth: 3)
								.foregroundStyle(.indigo.opacity(0.4))
								//.stroke(Color(nodeColor.darker()), lineWidth: 3)
								//.foregroundStyle(Color(nodeColor).opacity(0.4))
						}
						/// Position Annotations
						ForEach(Array(positions), id: \.id) { position in
							/// Node color from node.num
							let nodeColor = UIColor(hex: UInt32(position.nodePosition?.num ?? 0))
							Annotation(position.nodePosition?.user?.longName ?? "?", coordinate: position.coordinate) {
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
									CircleText(text: position.nodePosition?.user?.shortName ?? "?", color: Color(nodeColor), circleSize: 40)
								}
								.onTapGesture { location in
									selectedPosition = (selectedPosition == position ? nil : position)
								}
							}
							/// Route Lines
							if showRouteLines  {
								let positionArray = position.nodePosition?.positions?.array as? [PositionEntity] ?? []
								let routeCoords = positionArray.compactMap({(position) -> CLLocationCoordinate2D in
									return position.nodeCoordinate ?? LocationHelper.DefaultLocation
								})
								if showRouteLines {
									let gradient = LinearGradient(
										colors: [Color(nodeColor.lighter().lighter()), Color(nodeColor.lighter()), Color(nodeColor)],
										startPoint: .leading, endPoint: .trailing
									)
									let dashed = StrokeStyle(
										lineWidth: 3,
										lineCap: .round, lineJoin: .round, dash: [10, 10]
									)
									MapPolyline(coordinates: routeCoords)
										.stroke(gradient, style: dashed)
								}
							}
							/// Node History
							if showNodeHistory {
								ForEach(Array(position.nodePosition!.positions!) as! [PositionEntity], id: \.self) { (mappin: PositionEntity) in
									if mappin.latest == false { //} position.nodePosition.user.vip ?? false {
										let pf = PositionFlags(rawValue: Int(mappin.nodePosition?.metadata?.positionFlags ?? 771))
										let headingDegrees = Angle.degrees(Double(mappin.heading))
										Annotation("", coordinate: mappin.coordinate) {
											ZStack {
												if pf.contains(.Heading) {
													Image(systemName: "location.north.circle")
														.resizable()
														.scaledToFit()
														.foregroundStyle(Color(UIColor(hex: UInt32(mappin.nodePosition?.num ?? 0))).isLight() ? .black : .white)
														.background(Color(UIColor(hex: UInt32(mappin.nodePosition?.num ?? 0))))
														.clipShape(Circle())
														.rotationEffect(headingDegrees)
														.frame(width: 16, height: 16)
											
												} else {
													Circle()
														.fill(Color(UIColor(hex: UInt32(mappin.nodePosition?.num ?? 0))))
														.strokeBorder(Color(UIColor(hex: UInt32(mappin.nodePosition?.num ?? 0))).isLight() ? .black : .white ,lineWidth: 2)
														.frame(width: 12, height: 12)
												}
											}
										}
										.annotationTitles(.hidden)
										.annotationSubtitles(.hidden)
									}
								}
							}
						}
					}
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
			.mapScope(mapScope)
			.mapStyle(mapStyle)
			.mapControls {
				MapScaleView(scope: mapScope)
					.mapControlVisibility(.visible)
				if showUserLocation {
					MapUserLocationButton(scope: mapScope)
						.mapControlVisibility(.visible)
				}
				MapPitchToggle(scope: mapScope)
					.mapControlVisibility(.visible)
				MapCompass(scope: mapScope)
					.mapControlVisibility(.visible)
			}
			.controlSize(.regular)
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
				MapSettingsForm(nodeHistory: $showNodeHistory, routeLines: $showRouteLines, convexHull: $showConvexHull, traffic: $showTraffic, pointsOfInterest: $showPointsOfInterest, mapLayer: $selectedMapLayer)
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
