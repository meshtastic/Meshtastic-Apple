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
	@State private var position = MapCameraPosition.automatic
	@State private var scene: MKLookAroundScene?
	@State private var showUserLocation: Bool = false
	/// Unused map items
	@State private var selectedMapLayer: MapLayer = .standard
	@State var waypointCoordinate: WaypointCoordinate?
	@State var editingWaypoint: Int = 0

	/// Data
	@ObservedObject var node: NodeInfoEntity
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>
	
	
	var body: some View {
		let nodeColor = UIColor(hex: UInt32(node.num))
		let positionArray = node.positions?.array as? [PositionEntity] ?? []
		let mostRecent = node.positions?.lastObject as? PositionEntity
		let lineCoords = positionArray.compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationHelper.DefaultLocation
		})

		if mostRecent != nil {
			ZStack {
				Map(position: $position, bounds: MapCameraBounds(minimumDistance: 100, maximumDistance: .infinity), scope: mapScope) {
					/// Route Lines
					if showRouteLines {
						let gradient = LinearGradient(
							colors: [Color(nodeColor.lighter().lighter().lighter()), Color(nodeColor.lighter()), Color(nodeColor)],
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
										Image(systemName: pf.contains(.Speed) && position.speed > 1 ? "location.north.fill" : "location.north")
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
						.tag(position.time)
					}
				}
				.mapScope(mapScope)
				.mapStyle(.hybrid(elevation: .realistic))
				.mapControls {
					MapScaleView(scope: mapScope)
						.mapControlVisibility(.visible)
					if showUserLocation {
						MapUserLocationButton(scope: mapScope)
							.mapControlVisibility(.visible)
					}
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
				.overlay(alignment: .bottom) {
					if scene != nil {
						LookAroundPreview(scene: $scene, allowsNavigation: false, badgePosition: .bottomTrailing)
							.frame(height: 175)
							.clipShape(RoundedRectangle(cornerRadius: 12))
							.safeAreaPadding(.bottom, UIDevice.current.userInterfaceIdiom == .phone ? 30 : 75)
							.padding(.horizontal, 20)
					}
				}
				.onChange(of: node) {
					print("Node changed")
					let mostRecent = node.positions?.lastObject as? PositionEntity
					position = .camera(MapCamera(centerCoordinate: mostRecent!.coordinate, distance: 1500, heading: 0, pitch: 60))
				}
				.onChange(of: mostRecent) {
					if let mostRecent {
						Task {
							scene = try? await fetchScene(for: mostRecent.coordinate)
						}
					}
				}
				.onAppear {
					if self.scene == nil {
						Task {
							scene = try? await fetchScene(for: mostRecent!.coordinate)
						}
					}
				}
							
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
	
	private func fetchScene(for coordinate: CLLocationCoordinate2D) async throws -> MKLookAroundScene? {
			let lookAroundScene = MKLookAroundSceneRequest(coordinate: coordinate)
			return try await lookAroundScene.scene
	}
}
