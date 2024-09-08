//
//  MeshMapContent.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/17/24.
//

import SwiftUI
import MapKit

@available(iOS 17.0, macOS 14.0, *)
struct MeshMapContent: MapContent {

	/// Parameters
	@Binding var showUserLocation: Bool
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowLocationPrecision") private var showLocationPrecision = true
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
	@AppStorage("enableMapConvexHull") private var showConvexHull = false
	@Binding var showTraffic: Bool
	@Binding var showPointsOfInterest: Bool
	@Binding var selectedMapLayer: MapLayer
	// Map Configuration
	@Binding var selectedPosition: PositionEntity?
	@AppStorage("enableMapWaypoints") private var showWaypoints = false
	@Binding var selectedWaypoint: WaypointEntity?

	@FetchRequest(fetchRequest: PositionEntity.allPositionsFetchRequest(), animation: .easeIn)
	var positions: FetchedResults<PositionEntity>

	@FetchRequest(fetchRequest: WaypointEntity.allWaypointssFetchRequest(), animation: .none)
	var waypoints: FetchedResults<WaypointEntity>

	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
				  predicate: NSPredicate(format: "enabled == true", ""), animation: .none)
	private var routes: FetchedResults<RouteEntity>

	var delay: Double = 0
	@State private var scale: CGFloat = 0.5

	@MapContentBuilder
	var positionAnnotations: some MapContent {
		ForEach(positions, id: \.id) { position in
			/// Node color from node.num
			let nodeColor = UIColor(hex: UInt32(position.nodePosition?.num ?? 0))
			let positionName = position.nodePosition?.user?.longName ?? "?"
			/// Latest Position Anotations
			Annotation(positionName, coordinate: position.coordinate) {
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
				.onTapGesture { _ in
					selectedPosition = (selectedPosition == position ? nil : position)
				}
			}
			/// Node History and Route Lines for favorites
			if let nodePosition = position.nodePosition,
			   nodePosition.favorite,
			   let positions = nodePosition.positions,
			   let nodePositions = Array(positions) as? [PositionEntity] {
				if showRouteLines {
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
					ForEach(nodePositions, id: \.self) { (mappin: PositionEntity) in
						if mappin.latest == false && mappin.nodePosition?.favorite ?? false {
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
											.strokeBorder(Color(UIColor(hex: UInt32(mappin.nodePosition?.num ?? 0))).isLight() ? .black : .white, lineWidth: 2)
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
			if 10...19 ~= position.precisionBits {
				let pp = PositionPrecision(rawValue: Int(position.precisionBits))
				let radius: CLLocationDistance = pp?.precisionMeters ?? 0
				if radius > 0.0 && showLocationPrecision {
					MapCircle(center: position.coordinate, radius: radius)
						.foregroundStyle(Color(nodeColor).opacity(0.25))
						.stroke(.white, lineWidth: 2)
						.tag(position.nodePosition?.num ?? 0)
				}
			}
		}
	}

	@MapContentBuilder
	var routeAnnotations: some MapContent {
		ForEach(routes) { route in
			if let routeLocations = route.locations, let locations = Array(routeLocations) as? [LocationEntity] {
				let routeCoords = locations.compactMap {(loc) -> CLLocationCoordinate2D in
					return loc.locationCoordinate ?? LocationHelper.DefaultLocation
				}
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
	}

	@MapContentBuilder
	var waypointAnnotations: some MapContent {
		if waypoints.count > 0, showWaypoints, let waypoints = Array(waypoints) as? [WaypointEntity] {
			ForEach(waypoints, id: \.self) { waypoint in
				Annotation(waypoint.name ?? "?", coordinate: waypoint.coordinate) {
					LazyVStack {
						ZStack {
							CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 40)
								.onTapGesture(perform: { _ in
									selectedWaypoint = (selectedWaypoint == waypoint ? nil : waypoint)
								})
						}
					}
				}
			}
		}
	}

	@MapContentBuilder
	var meshMap: some MapContent {
		let loraNodes = positions.filter { $0.nodePosition?.viaMqtt ?? true == false }
		let loraCoords = Array(loraNodes).compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationsHandler.DefaultLocation
		})
		/// Convex Hull
		if showConvexHull {
			if loraCoords.count > 0 {
				let hull = loraCoords.getConvexHull()
				MapPolygon(coordinates: hull)
					.stroke(.blue, lineWidth: 3)
					.foregroundStyle(.indigo.opacity(0.4))
			}
		}
		positionAnnotations
		routeAnnotations
		waypointAnnotations
	}

	@MapContentBuilder
	var body: some MapContent {
		meshMap
	}
}
