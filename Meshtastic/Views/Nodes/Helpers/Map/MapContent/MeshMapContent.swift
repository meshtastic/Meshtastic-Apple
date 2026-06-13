//
//  MeshMapContent.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/17/24.
//

import SwiftUI
@preconcurrency import SwiftData
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

struct MeshMapSelectedNode: Identifiable, Equatable {
	let id: Int64
}

/// Lightweight snapshot of a position's node data, extracted outside MapContent
/// so MapKit reevaluations do not repeatedly fault SwiftData relationships.
struct MeshMapPositionSnapshot: Identifiable {
	let id: Int64
	let coordinate: CLLocationCoordinate2D
	let latitudeI: Int32
	let longitudeI: Int32
	let precisionBits: Int32
	let nodeNum: Int64
	let longName: String
	let shortName: String?
	let isOnline: Bool
	let viaMqtt: Bool
	let calculatedDelay: Double
}

struct MeshMapContent: MapContent {
	private let pulsingAnnotationLimit = 500

	/// Parameters
	@Binding var showUserLocation: Bool
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
	@AppStorage("enableMapConvexHull") private var showConvexHull = false
	@Binding var showTraffic: Bool
	@Binding var showPointsOfInterest: Bool
	@Binding var selectedMapLayer: MapLayer
	// Map Configuration
	@Binding var selectedNode: MeshMapSelectedNode?
	@AppStorage("enableMapWaypoints") private var showWaypoints = true
	@Binding var selectedWaypoint: WaypointEntity?
	// Map overlays
	@AppStorage("mapOverlaysEnabled") private var showMapOverlays = false
	@Binding var enabledOverlayConfigs: Set<UUID>
	
	/// Pre-filtered, pre-extracted positions passed in from the parent view.
	var positionSnapshots: [MeshMapPositionSnapshot]

	@Query(sort: \WaypointEntity.name, order: .reverse)
	var waypoints: [WaypointEntity]

	@Query(filter: #Predicate<RouteEntity> { $0.enabled == true },
		   sort: \RouteEntity.name)
	private var routes: [RouteEntity]

	@MapContentBuilder
	func positionAnnotations(snapshots: [MeshMapPositionSnapshot], showsPulse: Bool) -> some MapContent {
		ForEach(snapshots) { snap in
			Annotation(snap.longName, coordinate: snap.coordinate) {
				AnimatedNodePin(
					nodeColor: UIColor(hex: UInt32(snap.nodeNum)),
					shortName: snap.shortName,
					hasDetectionSensorMetrics: false,
					isOnline: snap.isOnline,
					calculatedDelay: snap.calculatedDelay,
					showsPulse: showsPulse
				)
					.equatable()
					.highPriorityGesture(TapGesture().onEnded { _ in
						selectedNode = (selectedNode?.id == snap.nodeNum ? nil : MeshMapSelectedNode(id: snap.nodeNum))
					})
			}
		}
	}

	@MapContentBuilder
	func densePositionAnnotations(snapshots: [MeshMapPositionSnapshot]) -> some MapContent {
		ForEach(snapshots) { snap in
			let nodeColor = Color(UIColor(hex: UInt32(snap.nodeNum)))
			Annotation(snap.longName, coordinate: snap.coordinate) {
				Circle()
					.fill(nodeColor.opacity(snap.isOnline ? 0.9 : 0.6))
					.stroke(.white.opacity(0.85), lineWidth: 1)
					.frame(width: snap.isOnline ? 10 : 8, height: snap.isOnline ? 10 : 8)
					.contentShape(Circle())
					.highPriorityGesture(TapGesture().onEnded { _ in
						selectedNode = (selectedNode?.id == snap.nodeNum ? nil : MeshMapSelectedNode(id: snap.nodeNum))
					})
			}
			.annotationTitles(.hidden)
			.annotationSubtitles(.hidden)
		}
	}

	private var reducedPrecisionCircleItems: [(nodeNum: Int64, circleKey: ReducedPrecisionMapCircleKey)] {
		var lowestNumForKey: [ReducedPrecisionMapCircleKey: Int64] = [:]
		for snapshot in positionSnapshots where 12...15 ~= snapshot.precisionBits {
			let nodeNum = snapshot.nodeNum
			let key = ReducedPrecisionMapCircleKey(latitudeI: snapshot.latitudeI, longitudeI: snapshot.longitudeI, precisionBits: snapshot.precisionBits)
			if let existing = lowestNumForKey[key] {
				if nodeNum < existing { lowestNumForKey[key] = nodeNum }
			} else {
				lowestNumForKey[key] = nodeNum
			}
		}
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
							.fill(Color.green)
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
		// When snapshots are empty (tab off-screen), skip all expensive content
		// to reduce memory from MapKit annotation/overlay view trees.
		if !positionSnapshots.isEmpty {
			let snapshots = positionSnapshots
			let isDense = snapshots.count > pulsingAnnotationLimit
			// Only compute LoRa node coordinates when the convex hull is actually displayed.
			let loraCoords: [CLLocationCoordinate2D] = showConvexHull
				? snapshots
					.filter { !$0.viaMqtt }
					.map(\.coordinate)
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

			if isDense {
				densePositionAnnotations(snapshots: snapshots)
			} else {
				positionAnnotations(snapshots: snapshots, showsPulse: true)
				reducedPrecisionMapCircles
			}
			routeAnnotations
			waypointAnnotations
		}
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
