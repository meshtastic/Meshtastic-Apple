//
//  RouteLines.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/14/24.
//
import SwiftUI
import MapKit

@available(iOS 17.0, macOS 14.0, *)
struct NodeMapContent: MapContent {
	
	@ObservedObject var node: NodeInfoEntity
	@State var showUserLocation: Bool = false
	@State var positions: [PositionEntity] = []
	/// Map State User Defaults
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
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
	@State var showWaypoints = false
	@State var selectedWaypoint: WaypointEntity?
	@State var isMeshMap = false
	
	//let region: MKCoordinateRegion
	
	
	@MapContentBuilder
	var nodeMap: some MapContent {
		let positionArray = node.positions?.array as? [PositionEntity] ?? []
		let lineCoords = positionArray.compactMap({(position) -> CLLocationCoordinate2D in
			return position.nodeCoordinate ?? LocationsHandler.DefaultLocation
		})
		/// Node Color from node.num
		let nodeColor = UIColor(hex: UInt32(node.num))
		
		
		/// Node Annotations
		ForEach(positionArray, id: \.id) { position in
			let pf = PositionFlags(rawValue: Int(position.nodePosition?.metadata?.positionFlags ?? 771))
			let headingDegrees = Angle.degrees(Double(position.heading))
			/// Reduced Precision Map Circle
			if position.latest && 11...16 ~= position.precisionBits {
				let pp = PositionPrecision(rawValue: Int(position.precisionBits))
				let radius : CLLocationDistance = pp?.precisionMeters ?? 0
				if radius > 0.0 {
					MapCircle(center: position.coordinate, radius: radius)
						.foregroundStyle(Color(nodeColor).opacity(0.25))
						.stroke(.white, lineWidth: 2)
				}
			}
			if showConvexHull {
				if lineCoords.count > 0 {
					let hull = lineCoords.getConvexHull()
					MapPolygon(coordinates: hull)
						.stroke(Color(nodeColor.darker()), lineWidth: 3)
						.foregroundStyle(Color(nodeColor).opacity(0.4))
				}
			}
			/// Route Lines
			if showRouteLines  {
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
			
			/// Node Annotations
			ForEach(positionArray, id: \.id) { position in
				Annotation(position.latest ? node.user?.shortName ?? "?": "", coordinate: position.coordinate) {
					LazyVStack {
						if position.latest {
							ZStack {
								Circle()
									.fill(Color(nodeColor.lighter()).opacity(0.4).shadow(.drop(color: Color(nodeColor).isLight() ? .black : .white, radius: 5)))
									.foregroundStyle(Color(nodeColor.lighter()).opacity(0.3))
									.frame(width: 50, height: 50)
									if pf.contains(.Heading) {
										Image(systemName: pf.contains(.Speed) && position.speed > 1 ? "location.north" : "octagon")
											.symbolEffect(.pulse.byLayer)
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
						} else {
							if showNodeHistory {
								if pf.contains(.Heading) {
									Image(systemName: "location.north.circle")
										.resizable()
										.scaledToFit()
										.foregroundStyle(Color(UIColor(hex: UInt32(node.num))).isLight() ? .black : .white)
										.background(Color(UIColor(hex: UInt32(node.num))))
										.clipShape(Circle())
										.rotationEffect(headingDegrees)
										.frame(width: 16, height: 16)

								} else {
									Circle()
										.fill(Color(UIColor(hex: UInt32(node.num))))
										.strokeBorder(Color(UIColor(hex: UInt32(node.num))).isLight() ? .black : .white ,lineWidth: 2)
										.frame(width: 12, height: 12)
								}
							}
						}
					}
				}
				.tag(position.time)
				.annotationTitles(.automatic)
				.annotationSubtitles(.automatic)
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
