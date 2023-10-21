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
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = true
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = true
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
	@State var isEditingSettings = false
	@State var selected: PositionEntity?
	@State var showWaypoints = false
	@State var selectedWaypoint: WaypointEntity?
	@State var showingPositionPopover = false
	
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>
	
	var body: some View {
		
		let positionArray = node.positions?.array as? [PositionEntity] ?? []
		let mostRecent = node.positions?.lastObject as? PositionEntity
		let lineCoords = positionArray.compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationHelper.DefaultLocation
		})
		
		if node.hasPositions {
			ZStack {
				MapReader { reader in
					Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity), scope: mapScope) {
						/// Node Color from node.num
						let nodeColor = UIColor(hex: UInt32(node.num))
						/// Route Lines
						if showRouteLines  {
							if showRouteLines {
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
						}
						/// Convex Hull
						if showConvexHull {
							let hull = lineCoords.getConvexHull()
							MapPolygon(coordinates: hull)
								.stroke(Color(nodeColor.darker()), lineWidth: 3)
								.foregroundStyle(Color(nodeColor).opacity(0.4))
						}
						
						/// Waypoint Annotations
						if showWaypoints {
							ForEach(Array(waypoints), id: \.id) { waypoint in
								Annotation(waypoint.name ?? "?", coordinate: waypoint.coordinate) {
									ZStack {
										CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 35)
										
											.onTapGesture(coordinateSpace: .named("nodemap")) { location in
												print("Tapped at \(location)")
												let pinLocation = reader.convert(location, from: .local)
												selectedWaypoint = (selectedWaypoint == waypoint ? nil : waypoint)
											}
									}
								}
							}
						}
						/// Node Annotations
						ForEach(positionArray, id: \.id) { position in
							let pf = PositionFlags(rawValue: Int(position.nodePosition?.metadata?.positionFlags ?? 3))
							let formatter = MeasurementFormatter()
							let headingDegrees = Angle.degrees(Double(position.heading))
							Annotation(position.latest ? node.user?.shortName ?? "?": "", coordinate: position.coordinate) {
								ZStack {
									if position.latest {
										Circle()
											.fill(Color(nodeColor.lighter()).opacity(0.4).shadow(.drop(color: Color(nodeColor).isLight() ? .black : .white, radius: 5)))
											.foregroundStyle(Color(nodeColor.lighter()).opacity(0.3))
											.frame(width: 50, height: 50)
										if pf.contains(.Heading) {
											Image(systemName: pf.contains(.Speed) && position.speed > 1 ? "location.north" : "octagon")
												.symbolEffect(.pulse.byLayer)
												.padding(5)
												.foregroundStyle(Color(nodeColor).isLight() ? .black : .white)
												.background(Color(UIColor(hex: UInt32(node.num)).darker()))
												.clipShape(Circle())
												.rotationEffect(headingDegrees)
												.onTapGesture {
													showingPositionPopover = true
													selected = (selected == position ? nil : position) // <-- here
												}
												.popover(isPresented: $showingPositionPopover) {
													PositionPopover(position: position)
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
													showingPositionPopover = true
													selected = (selected == position ? nil : position) // <-- here
												}
												.popover(isPresented: $showingPositionPopover, arrowEdge: .bottom) {
													PositionPopover(position: position)
														.tag(position.id)
														.padding()
														.opacity(0.8)
														.presentationCompactAdaptation(.popover)
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
					.sheet(item: $selectedWaypoint) { selection in
						WaypointPopover(waypoint: selection)
							.padding()
					}
					.sheet(isPresented: $isEditingSettings) {
						VStack {
							Form {
								Section(header: Text("Map Options")) {
									Picker(selection: $selectedMapLayer, label: Text("")) {
										ForEach(MapLayer.allCases, id: \.self) { layer in
											if layer != MapLayer.offline {
												Text(layer.localized)
											}
										}
									}
									.pickerStyle(SegmentedPickerStyle())
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
									.padding(.top, 5)
									.padding(.bottom, 5)
									Toggle(isOn: $showNodeHistory) {
										Label("Node History", systemImage: "building.columns.fill")
									}
									.toggleStyle(SwitchToggleStyle(tint: .accentColor))
									.onTapGesture {
										self.showNodeHistory.toggle()
										UserDefaults.enableMapNodeHistoryPins = self.showNodeHistory
									}
									Toggle(isOn: $showRouteLines) {
										Label("Route Lines", systemImage: "road.lanes")
									}
									.toggleStyle(SwitchToggleStyle(tint: .accentColor))
									.onTapGesture {
										self.showRouteLines.toggle()
										UserDefaults.enableMapRouteLines = self.showRouteLines
									}
									Toggle(isOn: $showConvexHull) {
										Label("Convex Hull", systemImage: "button.angledbottom.horizontal.right")
									}
									.toggleStyle(SwitchToggleStyle(tint: .accentColor))
									.onTapGesture {
										self.showConvexHull.toggle()
										UserDefaults.enableMapConvexHull = self.showConvexHull
									}
									Toggle(isOn: $showTraffic) {
										Label("Traffic", systemImage: "car")
									}
									.toggleStyle(SwitchToggleStyle(tint: .accentColor))
									.onTapGesture {
										self.showTraffic.toggle()
										UserDefaults.enableMapTraffic = self.showTraffic
									}
									Toggle(isOn: $showPointsOfInterest) {
										Label("Points of Interest", systemImage: "mappin.and.ellipse")
									}
									.toggleStyle(SwitchToggleStyle(tint: .accentColor))
									.onTapGesture {
										self.showPointsOfInterest.toggle()
										UserDefaults.enableMapPointsOfInterest = self.showPointsOfInterest
									}
								}
							}
							#if targetEnvironment(macCatalyst)
							Button {
								isEditingSettings = false
							} label: {
								Label("close", systemImage: "xmark")
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.large)
							.padding()
							#endif
						}
						.presentationDetents([.fraction(0.4), .medium])
						.presentationDragIndicator(.visible)
						
					}
					.onChange(of: node) {
						let mostRecent = node.positions?.lastObject as? PositionEntity
						position =  MapCameraPosition.automatic//.camera(MapCamera(centerCoordinate: mostRecent!.coordinate, distance: 1500, heading: 0, pitch: 0))
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
							
							#if targetEnvironment(macCatalyst)
							/// Hide non fuctional catalyst controls
//							MapZoomStepper(scope: mapScope)
//								.mapControlVisibility(.visible)
//							MapPitchSlider(scope: mapScope)
//								.mapControlVisibility(.visible)
							#endif
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
