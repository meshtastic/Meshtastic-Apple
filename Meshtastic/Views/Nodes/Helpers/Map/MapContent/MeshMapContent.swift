//
//  MeshMapContent.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/17/24.
//

import SwiftUI
import MapKit

import SwiftUI
import MapKit

@available(iOS 17.0, macOS 14.0, *)
struct MeshMapContent: MapContent {
	
	//@State var waypoints: [WaypointEntity] = []
	@State var routes: [RouteEntity] = []
	/// Parameters
	@Binding var showUserLocation: Bool
	@Binding var showNodeHistory: Bool
	@Binding var showRouteLines: Bool
	@Binding var showConvexHull: Bool
	@Binding var showTraffic: Bool
	@Binding var showPointsOfInterest: Bool
	@Binding var selectedMapLayer: MapLayer
	// Map Configuration
	@Binding var selectedPosition: PositionEntity?
	@Binding var showWaypoints: Bool
	@Binding var selectedWaypoint: WaypointEntity?
	
	@FetchRequest(fetchRequest: PositionEntity.allPositionsFetchRequest(), animation: .easeIn)
	var positions: FetchedResults<PositionEntity>
	
	@FetchRequest(fetchRequest: WaypointEntity.allWaypointssFetchRequest(), animation: .none)
	var waypoints: FetchedResults<WaypointEntity>

	var delay: Double = 0
	@State private var scale: CGFloat = 0.5

	@MapContentBuilder
	var meshMap: some MapContent {
		let lineCoords = Array(positions).compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationsHandler.DefaultLocation
		})
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
			/// Latest Position Anotations
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
			
			/// Node History and Route Lines for favorites
			if position.nodePosition?.user?.vip ?? false {
				if showRouteLines {
					let nodePositions = Array(position.nodePosition!.positions!) as! [PositionEntity]
					let routeCoords = nodePositions.compactMap({(pos) -> CLLocationCoordinate2D in
						return pos.nodeCoordinate ?? LocationHelper.DefaultLocation
					})
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
				if showNodeHistory {
					ForEach(Array(position.nodePosition!.positions!) as! [PositionEntity], id: \.self) { (mappin: PositionEntity) in
						if mappin.latest == false && mappin.nodePosition?.user?.vip ?? false {
							let pf = PositionFlags(rawValue: Int(mappin.nodePosition?.metadata?.positionFlags ?? 771))
							let headingDegrees = Angle.degrees(Double(mappin.heading))
							Annotation("", coordinate: mappin.coordinate) {
								LazyVStack {
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
			ForEach(Array(routes)) { route in
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
			ForEach(Array(waypoints) as! [WaypointEntity], id: \.self) { waypoint in
				Annotation(waypoint.name ?? "?", coordinate: waypoint.coordinate) {
					LazyVStack {
						ZStack {
							CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 40)
								.onTapGesture(perform: { location in
									selectedWaypoint = (selectedWaypoint == waypoint ? nil : waypoint)
								})
						}
					}
				}
			}
		}
	}
	
	@MapContentBuilder
	var body: some MapContent {
		meshMap
		
	}
}
