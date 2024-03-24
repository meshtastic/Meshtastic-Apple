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
	
	@State var positions: [PositionEntity] = []
	@State var waypoints: [WaypointEntity] = []
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
	//@Binding var editingWaypoint: WaypointEntity?
	@Binding var selectedWaypoint: WaypointEntity?

	var delay: Double = 0
	@State private var scale: CGFloat = 0.5

	@MapContentBuilder
	var meshMap: some MapContent {
		let lineCoords = positions.compactMap({(position) -> CLLocationCoordinate2D in
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
	
	@MapContentBuilder
	var body: some MapContent {
		if positions.count > 0 {
			meshMap
		}
	}
}
