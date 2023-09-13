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
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	/// Map State
	@Namespace var mapScope
	@AppStorage("meshMapType") private var meshMapType = 0
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
	
	@State private var selectedMapLayer: MapLayer = .standard
	@State var waypointCoordinate: WaypointCoordinate?
	@State var editingWaypoint: Int = 0

	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>
	@ObservedObject var node: NodeInfoEntity
		
	var body: some View {
		let nodeColor = UIColor(hex: UInt32(node.num))
		let positionArray = node.positions?.array as? [PositionEntity] ?? []
		let mostRecent = node.positions?.lastObject as? PositionEntity
		let lineCoords = positionArray.compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationHelper.DefaultLocation
		})

		if mostRecent != nil {
			NavigationStack {
				ZStack {
					Map(initialPosition: .camera(MapCamera(centerCoordinate: mostRecent!.coordinate, distance: 1000, heading: 0, pitch: 60)),
						bounds: MapCameraBounds(minimumDistance: 100, maximumDistance: .infinity),
						scope: mapScope) {
						/// Route Lines
						if showRouteLines {
							
							let gradient = LinearGradient(
								colors: [Color(nodeColor.lighter()), Color(nodeColor.lighter().lighter()), Color(nodeColor.lighter().lighter().lighter())],
								startPoint: .leading, endPoint: .trailing
							)
							let stroke = StrokeStyle(
								lineWidth: 5,
								lineCap: .round, lineJoin: .round, dash: [10, 10]
							)
							MapPolyline(coordinates: lineCoords)
								.stroke(gradient, style: stroke)
						}
						/// Node Annotations
						ForEach(positionArray.reversed(), id: \.id) { position in
							let pf = PositionFlags(rawValue: Int(position.nodePosition?.metadata?.positionFlags ?? 3))
							let formatter = MeasurementFormatter()
							let speedText = formatter.string(from: Measurement(value: Double(position.speed), unit: UnitSpeed.kilometersPerHour))
							Annotation(position.latest ? node.user?.shortName ?? "?" : (pf.contains(.Speed) && position.speed > 2) ? speedText : "", coordinate:  position.coordinate) {
								ZStack {
									if position.latest {
										Circle()
											.foregroundStyle(Color(nodeColor.lighter()).opacity(0.4))
												.frame(width: 60, height: 60)
										
										if pf.contains(.Heading) {
											Image(systemName: pf.contains(.Speed) && position.speed > 1 ? "location.north.fill" : "hexagon")
												.symbolEffect(.pulse.byLayer)
												.padding(5)
												.foregroundStyle(Color(nodeColor).isLight() ? .black : .white)
												.background(Color(UIColor(hex: UInt32(node.num)).darker()))
												.clipShape(Circle())
												.rotationEffect(.degrees(Double(position.heading)))
										} else {
											Image(systemName: "flipphone")
												.symbolEffect(.pulse.byLayer)
												.padding(5)
												.foregroundStyle(Color(nodeColor).isLight() ? .black : .white)
												.background(Color(UIColor(hex: UInt32(node.num)).darker()))
												.clipShape(Circle())
										}
									} else {
										if showNodeHistory {
											if pf.contains(.Heading) {
												Image(systemName: pf.contains(.Speed) && position.speed > 0 ? "location.north.fill" : "hexagon")
													.padding(2)
													.foregroundStyle(Color(UIColor(hex: UInt32(node.num)).lighter()).isLight() ? .black : .white)
													.background(Color(UIColor(hex: UInt32(node.num)).lighter()))
													.clipShape(Circle())
													.rotationEffect(.degrees(Double(position.heading)))
											} else {
												Image(systemName: "mappin.circle")
													.padding(2)
													.foregroundStyle(Color(UIColor(hex: UInt32(node.num)).lighter()).isLight() ? .black : .white)
													.background(Color(UIColor(hex: UInt32(node.num)).lighter()))
													.clipShape(Circle())
											}
										}
									}
								}
							}
							.tag(node.num)
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
					.controlSize(.regular)
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
