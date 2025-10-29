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
	/// Map State User Defaults
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
	@AppStorage("enableMapConvexHull") private var showConvexHull = false

	// Map Configuration
	@Namespace var mapScope
	@State var selectedPosition: PositionEntity?

	@MapContentBuilder
	var nodeMap: some MapContent {
		let positionArray = node.positions?.array as? [PositionEntity] ?? []

		/// Node Color from node.num
		let nodeColor = UIColor(hex: UInt32(node.num))
		let nodeColorSwift = Color(nodeColor)
		let nodeBorderColor: Color = nodeColorSwift.isLight() ? .black : .white

		// Prerender node history point views as UIImages for speedup when there are thousands of history points
		let prerenderedHistoryPointCircleImage = showNodeHistory ? prerenderHistoryPointCircle(fill: nodeColorSwift, stroke: nodeBorderColor) : UIImage()
		let prerenderedHistoryPointArrowImage = showNodeHistory ? prerenderHistoryPointArrow(fill: nodeColorSwift, stroke: nodeBorderColor) : UIImage()

		let pf = PositionFlags(rawValue: Int(node.metadata?.positionFlags ?? 771))

		/// Node Annotations
		ForEach(positionArray, id: \.id) { position in
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
										.foregroundStyle(nodeBorderColor)
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
										.foregroundStyle(nodeBorderColor)
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
				// Having showNodeHistory enabled can be quite slow if there are thousands of history points.
				if position.latest == false && node.favorite {
					let headingDegrees = Angle.degrees(Double(position.heading))
					Annotation("", coordinate: position.coordinate) {
						if pf.contains(.Heading) {
							Image(uiImage: prerenderedHistoryPointArrowImage)
								.renderingMode(.original)
								.interpolation(.none)
								.rotationEffect(headingDegrees)
								.frame(width: 16, height: 16)
								.allowsHitTesting(false)
								.accessibilityHidden(true)
						} else {
							Image(uiImage: prerenderedHistoryPointCircleImage)
								.renderingMode(.original)
								.interpolation(.none)
								.frame(width: 12, height: 12)
								.allowsHitTesting(false)
								.accessibilityHidden(true)
						}
					}
					.annotationTitles(.hidden)
					.annotationSubtitles(.hidden)
				}
			}
		}

		// Shared coordinate list for Route Lines and Convex Hull
		let allCoords: [CLLocationCoordinate2D] = (showRouteLines || showConvexHull) ? positionArray.compactMap(\.nodeCoordinate) : []

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
			MapPolyline(coordinates: allCoords)
				.stroke(gradient, style: dashed)
		}

		/// Convex Hull
		if showConvexHull {
			if allCoords.count > 0 {
				let hull = allCoords.getConvexHull()
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

	private func prerenderHistoryPointCircle(fill: Color, stroke: Color) -> UIImage {
		// Render to UIImage once so we don't have to do a ton of vector operations and layers when there are thousands of history points.
		let content = Circle()
			.fill(fill)
			.strokeBorder(stroke, lineWidth: 2)
			.frame(width: 12, height: 12)
		let renderer = ImageRenderer(content: content)
		renderer.scale = UIScreen.main.scale
		return renderer.uiImage!
	}

	private func prerenderHistoryPointArrow(fill: Color, stroke: Color) -> UIImage {
		// Render to UIImage once so we don't have to do a ton of vector operations and layers when there are thousands of history points.
		let content = Image(systemName: "location.north.circle")
			.resizable()
			.scaledToFit()
			.foregroundStyle(stroke)
			.background(fill)
			.clipShape(Circle())
		let renderer = ImageRenderer(content: content)
		renderer.scale = UIScreen.main.scale
		return renderer.uiImage!
	}
}
