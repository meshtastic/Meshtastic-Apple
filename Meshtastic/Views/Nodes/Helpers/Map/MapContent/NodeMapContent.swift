//
//  RouteLines.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/14/24.
//
import SwiftUI
import MapKit
import CoreData

struct NodeMapContent: MapContent {

	@ObservedObject var node: NodeInfoEntity
	@State var showUserLocation: Bool = false
	@State var positions: [PositionEntity] = []
	/// Map State User Defaults
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
	@AppStorage("enableMapWaypoints") private var showWaypoints = true
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
	@State var isShowingAltitude = false
	@State var isEditingSettings = false
	@State var selectedPosition: PositionEntity?
	@State var isMeshMap = false

	@MapContentBuilder
	var nodeMap: some MapContent {
		let positionArray = node.positions?.array as? [PositionEntity] ?? []
		let lineCoords = positionArray.compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationsHandler.DefaultLocation
		})

		/// Node Color from node.num
		let nodeColor = UIColor(hex: UInt32(node.num))
		let nodeColorSwift = Color(nodeColor)

		/// Node Annotations
		ForEach(positionArray, id: \.id) { position in

			let pf = PositionFlags(rawValue: Int(node.metadata?.positionFlags ?? 771))
			let headingDegrees = Angle.degrees(Double(position.heading))
			/// Reduced Precision Map Circle
			if position.latest && 12...15 ~= position.precisionBits {
				let pp = PositionPrecision(rawValue: Int(position.precisionBits))
				let radius: CLLocationDistance = pp?.precisionMeters ?? 0
				if radius > 0.0 {
					MapCircle(center: position.coordinate, radius: radius)
						.foregroundStyle(Color(nodeColor).opacity(0.25))
						.stroke(.white, lineWidth: 2)
				}
			}
			/// Lastest Position Pin
			if position.latest {
				/// Node Annotations
				Annotation(position.latest ? node.user?.shortName ?? "?": "", coordinate: position.coordinate) {
					LazyVStack {
							ZStack {
								if pf.contains(.Heading) {
									Image(systemName: pf.contains(.Speed) && position.speed > 1 ? "location.north" : "octagon")
										.padding(5)
										.foregroundStyle(Color(nodeColor).isLight() ? .black : .white)
										.background(Color(nodeColor.darker()))
										.clipShape(Circle())
										.rotationEffect(headingDegrees)
										.onTapGesture {
											selectedPosition = (selectedPosition == position ? nil : position)
										}
										.popover(item: $selectedPosition) { selection in
											PositionPopover(position: selection)
												.padding()
												.opacity(0.8)
												.presentationCompactAdaptation(.popover)
										}

								} else {
									Image(systemName: "flipphone")
										.symbolEffect(.pulse.byLayer)
										.padding(5)
										.foregroundStyle(Color(nodeColor).isLight() ? .black : .white)
										.background(Color(UIColor(hex: UInt32(node.num)).darker()))
										.clipShape(Circle())
										.onTapGesture {
											selectedPosition = (selectedPosition == position ? nil : position)
										}
										.popover(item: $selectedPosition) { selection in
											PositionPopover(position: selection)
												.padding()
												.opacity(0.8)
												.presentationCompactAdaptation(.popover)
										}
								}
							}
						}
					}
					.tag(position.time)
					.annotationTitles(.automatic)
					.annotationSubtitles(.automatic)
			}
			/// Node History
			if showNodeHistory {
				if position.latest == false && node.favorite {
					let pf = PositionFlags(rawValue: Int(node.metadata?.positionFlags ?? 771))
					let headingDegrees = Angle.degrees(Double(position.heading))
					Annotation("", coordinate: position.coordinate) {
						if pf.contains(.Heading) {
							Image(systemName: "location.north.circle")
								.resizable()
								.scaledToFit()
								.foregroundStyle(nodeColorSwift.isLight() ? .black : .white)
								.background(nodeColorSwift)
								.clipShape(Circle())
								.rotationEffect(headingDegrees)
								.frame(width: 16, height: 16)

						} else {
							Circle()
								.fill(nodeColorSwift)
								.strokeBorder(nodeColorSwift.isLight() ? .black : .white, lineWidth: 2)
								.frame(width: 12, height: 12)
						}
					}
					.annotationTitles(.hidden)
					.annotationSubtitles(.hidden)
				}
			}
		}

		/// Route Lines
		if showRouteLines {
			let gradient = LinearGradient(
				colors: [Color(nodeColor.lighter().lighter().lighter()), Color(nodeColor.lighter()), Color(nodeColor)],
				startPoint: .leading, endPoint: .trailing
			)
			let dashed = StrokeStyle(
				lineWidth: 3,
				lineCap: .round, lineJoin: .round, dash: [10, 10]
			)
			MapPolyline(coordinates: lineCoords)
				.stroke(gradient, style: dashed)
		}

		let loraNodes = positionArray.filter { $0.nodePosition?.viaMqtt ?? true == false }
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
	}

	@MapContentBuilder
	var body: some MapContent {
		if node.positions?.count ?? 0 > 0 {
			nodeMap
		}
	}
}
