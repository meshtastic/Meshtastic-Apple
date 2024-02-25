//
//  NodeMapSwiftUI.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/11/23.
//

import SwiftUI
import CoreLocation
#if canImport(MapKit)
import MapKit
#endif
import WeatherKit

@available(iOS 17.0, macOS 14.0, *)
struct NodeMapSwiftUI: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	/// Parameters
	@ObservedObject var node: NodeInfoEntity
	@State var showUserLocation: Bool = false
	@State var positions: [PositionEntity] = []
	/// Map State User Defaults
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
	@AppStorage("enableMapConvexHull") private var showConvexHull = false
	@AppStorage("enableMapTraffic") private var showTraffic: Bool = false
	@AppStorage("enableMapPointsOfInterest") private var showPointsOfInterest: Bool = false
	@AppStorage("mapLayer") private var selectedMapLayer: MapLayer = .hybrid
	// Map Configuration
	@Namespace var mapScope
	@State var mapStyle: MapStyle = MapStyle.hybrid(elevation: .realistic, pointsOfInterest: .all, showsTraffic: true)
	@State var position = MapCameraPosition.automatic
	@State var scene: MKLookAroundScene?
	@State var isLookingAround = false
	@State var isShowingAltitude = false
	@State var isEditingSettings = false
	@State var selectedPosition: PositionEntity?
	@State var showWaypoints = false
	@State var selectedWaypoint: WaypointEntity?
	@State var isMeshMap = false
	
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>
	
	var body: some View {
		
		let positionArray = node.positions?.array as? [PositionEntity] ?? []
		var mostRecent = node.positions?.lastObject as? PositionEntity
		let lineCoords = positionArray.compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationsHandler.DefaultLocation
		})
		
		if node.hasPositions {
			ZStack {
				MapReader { reader in
					Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity), scope: mapScope) {
						/// Node Color from node.num
						let nodeColor = UIColor(hex: UInt32(node.num))
						/// Route Lines
						if showRouteLines  {
							let gradient = LinearGradient(
								colors: [Color(nodeColor.lighter().lighter().lighter()), Color(nodeColor.lighter()), Color(nodeColor)],
								startPoint: .leading, endPoint: .trailing
							)
							let dashed = StrokeStyle(
								lineWidth: 3,
								lineCap: .round, lineJoin: .round, dash: [10, 10]
							)
							MapPolyline(coordinates: lineCoords)
								.stroke(gradient, style: dashed)
						}
						/// Convex Hull
						if showConvexHull {
							if lineCoords.count > 0 {
								let hull = lineCoords.getConvexHull()
								MapPolygon(coordinates: hull)
									.stroke(Color(nodeColor.darker()), lineWidth: 3)
									.foregroundStyle(Color(nodeColor).opacity(0.4))
							}
						}
						
						/// Waypoint Annotations
						if waypoints.count > 0 && showWaypoints {
							ForEach(Array(waypoints), id: \.id) { waypoint in
								Annotation(waypoint.name ?? "?", coordinate: waypoint.coordinate) {
									LazyVStack {
										CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 35)
											.onTapGesture(coordinateSpace: .named("nodemap")) { location in
												selectedWaypoint = (selectedWaypoint == waypoint ? nil : waypoint)
											}
									}
								}
							}
						}
						/// Node Annotations
						ForEach(positionArray, id: \.id) { position in
							let pf = PositionFlags(rawValue: Int(position.nodePosition?.metadata?.positionFlags ?? 771))
							let headingDegrees = Angle.degrees(Double(position.heading))
							/// Reduced Precision Map Circle
							if position.latest && 11...16 ~= position.precisionBits {
								let pp = PositionPrecision(rawValue: Int(position.precisionBits))
								let radius : CLLocationDistance = pp?.precisionMeters ?? 0
								if radius > 0.0 {
									MapCircle(center: position.coordinate, radius: radius)
									.foregroundStyle(Color(nodeColor).opacity(0.60))
								}
							}
							Annotation(position.latest ? node.user?.shortName ?? "?": "", coordinate: position.coordinate) {
								LazyVStack {
									if position.latest {
										ZStack {
											Circle()
												.fill(Color(nodeColor.lighter()).opacity(0.4).shadow(.drop(color: Color(nodeColor).isLight() ? .black : .white, radius: 5)))
												.foregroundStyle(Color(nodeColor.lighter()).opacity(0.3))
												.frame(width: 50, height: 50)
											if pf.contains(.Heading) {
												Image(systemName: pf.contains(.Speed) && position.speed > 1 ? "location.north" : "octagon")
													.symbolEffect(.pulse.byLayer)
													.padding(5)
													.foregroundStyle(Color(nodeColor).isLight() ? .black : .white)
													.background(Color(nodeColor.darker()))
													.clipShape(Circle())
													.rotationEffect(headingDegrees)
													.onTapGesture {
														selectedPosition = (selectedPosition == position ? nil : position)
													}
													.popover(item: $selectedPosition) { selection in
														PositionPopover(position: selection)
															.padding()
															.opacity(0.8)
															.presentationCompactAdaptation(.popover)
													}
												
											} else {
												Image(systemName: "flipphone")
													.symbolEffect(.pulse.byLayer)
													.padding(5)
													.foregroundStyle(Color(nodeColor).isLight() ? .black : .white)
													.background(Color(UIColor(hex: UInt32(node.num)).darker()))
													.clipShape(Circle())
													.onTapGesture {
														selectedPosition = (selectedPosition == position ? nil : position)
													}
													.popover(item: $selectedPosition) { selection in
														PositionPopover(position: selection)
															.padding()
															.opacity(0.8)
															.presentationCompactAdaptation(.popover)
													}
												
											}
										}
									} else {
										if showNodeHistory {
											if pf.contains(.Heading) {
												Image(systemName: "location.north.circle")
													.resizable()
													.scaledToFit()
													.foregroundStyle(Color(UIColor(hex: UInt32(node.num))).isLight() ? .black : .white)
													.background(Color(UIColor(hex: UInt32(node.num))))
													.clipShape(Circle())
													.rotationEffect(headingDegrees)
													.frame(width: 16, height: 16)
												
											} else {
												Circle()
													.fill(Color(UIColor(hex: UInt32(node.num))))
													.strokeBorder(Color(UIColor(hex: UInt32(node.num))).isLight() ? .black : .white ,lineWidth: 2)
													.frame(width: 12, height: 12)
											}
										}
									}
								}
							}
							.tag(position.time)
							.annotationTitles(.automatic)
							.annotationSubtitles(.automatic)
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
					.overlay(alignment: .bottom) {
						if scene != nil && isLookingAround {
							LookAroundPreview(initialScene: scene)
								.frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 250 : 400)
								.clipShape(RoundedRectangle(cornerRadius: 12))
								.padding(.horizontal, 20)
						}
					}
					.overlay(alignment: .bottom) {
						if !isLookingAround && isShowingAltitude {
							PositionAltitudeChart(node: node)
								.frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 250 : 400)
								.clipShape(RoundedRectangle(cornerRadius: 12))
								.padding(.horizontal, 20)
						}
					}
					.sheet(item: $selectedWaypoint) { selection in
						WaypointForm(waypoint: selection)
							.padding()
					}
					.sheet(isPresented: $isEditingSettings) {
						MapSettingsForm(nodeHistory: $showNodeHistory, routeLines: $showRouteLines, convexHull: $showConvexHull, traffic: $showTraffic, pointsOfInterest: $showPointsOfInterest, mapLayer: $selectedMapLayer, meshMap: $isMeshMap)
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
					}
					.onChange(of: node) {
						isLookingAround = false
						isShowingAltitude = false
						mostRecent = node.positions?.lastObject as? PositionEntity
						if node.positions?.count ?? 0 > 1 {
							position = .automatic
						} else {
							position = .camera(MapCamera(centerCoordinate: mostRecent!.coordinate, distance: 150, heading: 0, pitch: 60))
						}
						if let mostRecent {
							Task {
								scene = try? await fetchScene(for: mostRecent.coordinate)
							}
						}
					}
					.onAppear {
						UIApplication.shared.isIdleTimerDisabled = true
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
						mostRecent = node.positions?.lastObject as? PositionEntity
						if node.positions?.count ?? 0 > 1 {
							position = .automatic
						} else {
							position = .camera(MapCamera(centerCoordinate: mostRecent!.coordinate, distance: 5000, heading: 0, pitch: 60))
						}
						if self.scene == nil {
							Task {
								scene = try? await fetchScene(for: mostRecent!.coordinate)
							}
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
									if isShowingAltitude {
										isShowingAltitude = false
									}
									isLookingAround = !isLookingAround
								}) {
									Image(systemName: isLookingAround ? "binoculars.fill" : "binoculars")
										.padding(.vertical, 5)
								}
								.tint(Color(UIColor.secondarySystemBackground))
								.foregroundColor(.accentColor)
								.buttonStyle(.borderedProminent)
							}
							/// Altitude Button
							if node.positions?.count ?? 0 > 1 {
								Button(action: {
									if isLookingAround {
										isLookingAround = false
									}
									isShowingAltitude = !isShowingAltitude
								}) {
									Image(systemName: isShowingAltitude ? "mountain.2.fill" : "mountain.2")
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
					.onDisappear {
						UIApplication.shared.isIdleTimerDisabled = false
					}
				}}
			.navigationBarTitle(String((node.user?.shortName ?? "unknown".localized) + (" \(node.positions?.count ?? 0) points")), displayMode: .inline)
			.navigationBarItems(trailing:
									ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
			})
		} else {
			ContentUnavailableView("No Positions", systemImage: "mappin.slash")
		}
	}
	/// Get the look around scene
	private func fetchScene(for coordinate: CLLocationCoordinate2D) async throws -> MKLookAroundScene? {
		let lookAroundScene = MKLookAroundSceneRequest(coordinate: coordinate)
		return try await lookAroundScene.scene
	}
}
