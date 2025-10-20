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
	
	@MapContentBuilder
	var positionAnnotations: some MapContent {
		ForEach(positions, id: \.id) { position in
			if (!showFavorites || (position.nodePosition?.favorite == true)) && !(position.nodePosition?.ignored == true) {
				
				let nodeColor = UIColor(hex: UInt32(position.nodePosition?.num ?? 0))
				let positionName = position.nodePosition?.user?.longName ?? "?"
				// Use a hash of the position ID to stagger animation delays for each node, preventing synchronized animations and improving visual distinction.
				let calculatedDelay = Double(position.id.hashValue % 100) / 100.0 * 0.5
				
				let coordinateForNodePin: CLLocationCoordinate2D = if position.isPreciseLocation {
					// Precise location: place node pin at actual location.
					position.coordinate
				} else {
					// Imprecise location: fuzz slightly so overlapping nodes are visible and clickable at highest zoom levels.
					position.fuzzedCoordinate
				}

				Annotation(positionName, coordinate: coordinateForNodePin) {
					LazyVStack {
						AnimatedNodePin(
							nodeColor: nodeColor,
							shortName: position.nodePosition?.user?.shortName,
							hasDetectionSensorMetrics: position.nodePosition?.hasDetectionSensorMetrics ?? false,
							isOnline: position.nodePosition?.isOnline ?? false,
							calculatedDelay: calculatedDelay
						)
					}
					.highPriorityGesture(TapGesture().onEnded { _ in
						selectedPosition = (selectedPosition == position ? nil : position)
					})
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
				Annotation(String(localized: "Start"), coordinate: routeCoords.first ?? LocationsHandler.DefaultLocation) {
					ZStack {
						Circle()
							.fill(Color(.green))
							.strokeBorder(.white, lineWidth: 3)
							.frame(width: 15, height: 15)
					}
				}
				.annotationTitles(.automatic)
				Annotation(String(localized: "Finish ", comment: "Space at the end has been added to not interfere with translations for 'Finish' in RouteRecorder"), coordinate: routeCoords.last ?? LocationsHandler.DefaultLocation) {
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
						Annotation(feature.name, coordinate: coordinate) {
							Circle()
								.fill(styledFeature.fillColor)
								.stroke(styledFeature.strokeColor, style: styledFeature.strokeStyle)
								.frame(width: feature.markerRadius * 2, height: feature.markerRadius * 2)
						}
						.annotationTitles(.automatic)
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
