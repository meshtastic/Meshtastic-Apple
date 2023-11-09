//
//  MeshMap.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/23.
//

import SwiftUI
import CoreData
import CoreLocation
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
	@State var mapStyle: MapStyle = MapStyle.hybrid(elevation: .realistic, pointsOfInterest: .all, showsTraffic: true)
	@State var position = MapCameraPosition.automatic
	@State var scene: MKLookAroundScene?
	@State var isLookingAround = false
	@State var isEditingSettings = false
	@State var selectedPosition: PositionEntity?
	@State var showWaypoints = false
	@State var selectedWaypoint: WaypointEntity?
	
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
		NavigationStack {
			ZStack {
				MapReader { reader in
					Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity), scope: mapScope) {
						/// Waypoint Annotations
						if waypoints.count > 0 && showWaypoints {
							ForEach(Array(waypoints), id: \.id) { waypoint in
								Annotation(waypoint.name ?? "?", coordinate: waypoint.coordinate) {
									ZStack {
										CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 35)
											.onTapGesture(coordinateSpace: .named("meshmap")) { location in
												print("Tapped at \(location)")
												let pinLocation = reader.convert(location, from: .local)
												selectedWaypoint = (selectedWaypoint == waypoint ? nil : waypoint)
											}
									}
								}
							}
						}
						/// Position Annotations
						ForEach(Array(positions), id: \.id) { position in
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
								.onTapGesture(coordinateSpace: .named("meshmap")) { location in
									print("Tapped at \(location)")
									let pinLocation = reader.convert(location, from: .local)
									selectedPosition = (selectedPosition == position ? nil : position)
								}
							}
						}
					}
				}
			}
			.ignoresSafeArea(.all, edges: [.top, .leading, .trailing])
			.frame(maxHeight: .infinity)
//			.popover(item: $selectedPosition) { selection in
//				PositionPopover(position: selection)
//					.padding()
//					.opacity(0.8)
//					.presentationCompactAdaptation(.sheet)
//			}
			.sheet(item: $selectedPosition) { selection in
				PositionPopover(position: selection)
					.padding()
			}
		}
		.navigationTitle("Mesh Map")
		.navigationBarItems(leading:
								MeshtasticLogo(), trailing:
								ZStack {
			ConnectedDevice(
				bluetoothOn: bleManager.isSwitchedOn,
				deviceConnected: bleManager.connectedPeripheral != nil,
				name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName :
					"?")
		})
		.onAppear(perform: {
			UIApplication.shared.isIdleTimerDisabled = true
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
		})
		.onDisappear(perform: {
			UIApplication.shared.isIdleTimerDisabled = false
		})
	}
}
