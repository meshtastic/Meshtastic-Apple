//
//  MeshMapContent.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/17/24.
//

import SwiftUI
import MapKit
import CoreLocation
import OSLog

struct IdentifiableOverlay: Identifiable {
    let overlay: MKOverlay
    var id: ObjectIdentifier { ObjectIdentifier(overlay as AnyObject) }
}

struct MeshMapContent: MapContent {

	/// Parameters
	@Binding var showUserLocation: Bool
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
	@AppStorage("enableMapConvexHull") private var showConvexHull = false
	@AppStorage("enableMapShowFavorites") private var showFavorites = false
	@Binding var showTraffic: Bool
	@Binding var showPointsOfInterest: Bool
	@Binding var selectedMapLayer: MapLayer
	// Map Configuration
	@Binding var selectedPosition: PositionEntity?
	@AppStorage("enableMapWaypoints") private var showWaypoints = true
	@Binding var selectedWaypoint: WaypointEntity?

	// Map overlays
	@AppStorage("mapOverlaysEnabled") private var showMapOverlays = false
	@Binding var enabledOverlayConfigs: Set<UUID>

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
			if  !showFavorites || (position.nodePosition?.favorite == true) {
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
								.onChange(of: showFavorites) {

									scale = 0.5 // Reset to initial state
											DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
													scale = 1
											}
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
				.highPriorityGesture(TapGesture().onEnded { _ in
					selectedPosition = (selectedPosition == position ? nil : position)
				})
			}
			/// Node History and Route Lines for favorites
			if let nodePosition = position.nodePosition,
			   nodePosition.favorite,
			   let positions = nodePosition.positions,
			   let nodePositions = Array(positions) as? [PositionEntity] {
				if showRouteLines {
					let routeCoords = nodePositions.compactMap({(pos) -> CLLocationCoordinate2D in
						return pos.nodeCoordinate ?? LocationsHandler.DefaultLocation
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
			if 12...15 ~= position.precisionBits {
				let pp = PositionPrecision(rawValue: Int(position.precisionBits))
				let radius: CLLocationDistance = pp?.precisionMeters ?? 0
				if radius > 0.0 {
					MapCircle(center: position.coordinate, radius: radius)
						.foregroundStyle(Color(nodeColor).opacity(0.25))
						.stroke(.white, lineWidth: 2)
						.tag(position.nodePosition?.num ?? 0)
				}
			}
		}

	}
	}

	@MapContentBuilder
	var routeAnnotations: some MapContent {
		ForEach(routes) { route in
			if let routeLocations = route.locations, let locations = Array(routeLocations) as? [LocationEntity] {
				let routeCoords = locations.compactMap {(loc) -> CLLocationCoordinate2D in
					return loc.locationCoordinate ?? LocationsHandler.DefaultLocation
				}
				Annotation("Start", coordinate: routeCoords.first ?? LocationsHandler.DefaultLocation) {
					ZStack {
						Circle()
							.fill(Color(.green))
							.strokeBorder(.white, lineWidth: 3)
							.frame(width: 15, height: 15)
					}
				}
				.annotationTitles(.automatic)
				Annotation("Finish", coordinate: routeCoords.last ?? LocationsHandler.DefaultLocation) {
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
								.highPriorityGesture(TapGesture().onEnded { _ in
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

		/// GeoJSON Overlays with embedded styling
		if showMapOverlays {
			overlayContent
		}

		positionAnnotations
		routeAnnotations
		waypointAnnotations
	}

	var overlayContent: some MapContent {
		// Get all features but filter by enabled configs
		let allStyledFeatures = GeoJSONOverlayManager.shared.loadStyledFeaturesForConfigs(enabledOverlayConfigs)
		
		
		return Group {
			ForEach(0..<allStyledFeatures.count, id: \.self) { index in
				let styledFeature = allStyledFeatures[index]
				let feature = styledFeature.feature
				let geometryType = feature.geometry.type
				
				if geometryType == "Point" {
					if let coordinate = feature.geometry.coordinates.toCoordinate() {
						Annotation("", coordinate: coordinate) {
							Circle()
								.fill(styledFeature.fillColor)
								.stroke(styledFeature.strokeColor, style: styledFeature.strokeStyle)
								.frame(width: feature.markerRadius * 2, height: feature.markerRadius * 2)
						}
						.annotationTitles(.hidden)
						.annotationSubtitles(.hidden)
					}
				} else if geometryType == "LineString" {
					if let overlay = styledFeature.createOverlay() as? MKPolyline {
						MapPolyline(overlay)
							.stroke(styledFeature.strokeColor, style: styledFeature.strokeStyle)
					}
				} else if geometryType == "Polygon" {
					if let overlay = styledFeature.createOverlay() as? MKPolygon {
						MapPolygon(overlay)
							.foregroundStyle(styledFeature.fillColor)
							.stroke(styledFeature.strokeColor, style: styledFeature.strokeStyle)
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
