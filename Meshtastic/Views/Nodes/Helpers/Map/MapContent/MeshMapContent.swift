//
//  MeshMapContent.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/17/24.
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import OSLog

struct IdentifiableOverlay: Identifiable {
	let overlay: MKOverlay
	var id: ObjectIdentifier { ObjectIdentifier(overlay as AnyObject) }
}

struct ReducedPrecisionMapCircleKey: Hashable {
    let latitudeI: Int32
    let longitudeI: Int32
    let precisionBits: Int32
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
	
	@Query(filter: #Predicate<PositionEntity> { $0.nodePosition != nil && $0.latest == true },
		   sort: \PositionEntity.time, order: .reverse)
	var positions: [PositionEntity]

	@Query(sort: \WaypointEntity.name, order: .reverse)
	var waypoints: [WaypointEntity]

	@Query(filter: #Predicate<RouteEntity> { $0.enabled == true },
		   sort: \RouteEntity.name)
	private var routes: [RouteEntity]

	@MapContentBuilder
	var positionAnnotations: some MapContent {
		ForEach(positions, id: \.id) { position in
			/// Apply favorites filter and don't show ignored nodes
			if (!showFavorites || (position.nodePosition?.favorite == true)) && !(position.nodePosition?.ignored == true) {
				let coordinateForNodePin: CLLocationCoordinate2D = if position.isPreciseLocation {
					// Precise location: place node pin at actual location.
					position.nodeCoordinate ?? LocationsHandler.DefaultLocation
				} else {
					// Imprecise location: fuzz slightly so overlapping nodes are visible and clickable at highest zoom levels.
					position.fuzzedNodeCoordinate ?? LocationsHandler.DefaultLocation
				}
				if 12...15 ~= position.precisionBits || position.precisionBits == 32 {
					
					let nodeColor = UIColor(hex: UInt32(position.nodePosition?.num ?? 0))
					let positionName = position.nodePosition?.user?.longName ?? "?"

					// Use a hash of the position ID to stagger animation delays for each node, preventing synchronized animations and improving visual distinction.
					let calculatedDelay = Double(position.id.hashValue % 100) / 100.0 * 0.5
					
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
	}

	private var reducedPrecisionCircleItems: [(nodeNum: Int64, circleKey: ReducedPrecisionMapCircleKey)] {
		// Precompute *unique* reduced-precision circles so we don't have to redraw tons of identical (center, radius) circles in dense map areas. (Since they're all transparent, this causes severe FPS drop when zoomed into areas where there are a ton of overlapping circles.)
		var lowestNumForKey: [ReducedPrecisionMapCircleKey: Int64] = [:]
		// Populate a dict where the key is (lat, lon, bits) and the value is the *lowest* node.num seen for that key.
		// That lowest node.num value is used to create a stable color for the MapCircle and stable id for ForEach.
		for position in positions {
			// Same filter criteria as positionAnnotations:
			if (!showFavorites || (position.nodePosition?.favorite == true)) && !(position.nodePosition?.ignored == true) {
				if 12...15 ~= position.precisionBits {
					let nodeNum = position.nodePosition?.num ?? 0
					let key = ReducedPrecisionMapCircleKey(latitudeI: position.latitudeI, longitudeI: position.longitudeI, precisionBits: position.precisionBits)
					if let existing = lowestNumForKey[key] {
						if nodeNum < existing { lowestNumForKey[key] = nodeNum }
					} else {
						lowestNumForKey[key] = nodeNum
					}
				}
			}
		}
		// Sort by nodeNum just to keep draw order stable.
        return lowestNumForKey.map { ($0.value, $0.key) }.sorted { $0.nodeNum < $1.nodeNum }
	}

    @MapContentBuilder
    var reducedPrecisionMapCircles: some MapContent {
        ForEach(reducedPrecisionCircleItems, id: \.nodeNum) { item in
            let circleKey = item.circleKey
            let nodeNum = item.nodeNum
            let radius = PositionPrecision(rawValue: Int(circleKey.precisionBits))?.precisionMeters ?? 0
            if radius > 0.0 {
                let center = CLLocationCoordinate2D(latitude: Double(circleKey.latitudeI) / 1e7, longitude: Double(circleKey.longitudeI) / 1e7)
				let nodeColor = UIColor(hex: UInt32(nodeNum))
                MapCircle(center: center, radius: radius)
                    .foregroundStyle(Color(nodeColor).opacity(0.25))
                    .stroke(.white, lineWidth: 1)
            }
        }
    }

	@MapContentBuilder
	var routeAnnotations: some MapContent {
		ForEach(routes) { route in
			if !route.locations.isEmpty {
				let locations = route.locations
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
				Annotation(waypoint.name ?? "?", coordinate: waypoint.mapCoordinate) {
					LazyVStack {
						ZStack {
							CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 40)
								.highPriorityGesture(TapGesture().onEnded { _ in
									selectedWaypoint = (selectedWaypoint == waypoint ? nil : waypoint)
								})
						}
					}
				}
				.annotationTitles(.automatic) 
			}
		}
	}
	
	@MapContentBuilder
	var meshMap: some MapContent {
		// Only compute LoRa node coordinates when the convex hull is actually displayed.
		// The filter scans the entire positions array on every render, so guard it.
		let loraCoords: [CLLocationCoordinate2D] = showConvexHull
			? positions
				.filter { !($0.nodePosition?.viaMqtt ?? true) }
				.compactMap { $0.nodeCoordinate ?? LocationsHandler.DefaultLocation }
			: []
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
		reducedPrecisionMapCircles
		routeAnnotations
		waypointAnnotations
	}
	
	var overlayContent: some MapContent {
		// Get all features but filter by enabled configs
		let allStyledFeatures = GeoJSONOverlayManager.shared.loadStyledFeaturesForConfigs(enabledOverlayConfigs)
		
		return Group {
			// GeoJSONStyledFeature is Identifiable with a stable UUID assigned at creation.
			// Using ForEach with Identifiable gives SwiftUI stable identity for diffing,
			// avoiding full teardown/rebuild of overlay views on each render.
			ForEach(allStyledFeatures) { styledFeature in
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
