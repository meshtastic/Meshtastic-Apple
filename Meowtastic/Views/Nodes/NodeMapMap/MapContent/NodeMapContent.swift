import SwiftUI
import MapKit
import CoreData

struct NodeMapContent: MapContent {

	@ObservedObject
	var node: NodeInfoEntity
	@Namespace
	var mapScope
	@State
	var showUserLocation: Bool = false
	@State
	var mapStyle: MapStyle = MapStyle.standard(elevation: .realistic)
	@State
	var mapCamera = MapCameraPosition.automatic
	@State
	var scene: MKLookAroundScene?
	@State
	var isEditingSettings = false
	@State
	var selectedPosition: PositionEntity?
	@State
	var isMeshMap = false

	@AppStorage("meshMapShowNodeHistory")
	private var showNodeHistory = false
	@AppStorage("mapLayer")
	private var selectedMapLayer: MapLayer = .standard

	private var positions: [PositionEntity] {
		if let positionArray = node.positions?.array as? [PositionEntity] {
			positionArray
		}
		else {
			[]
		}
	}

	@MapContentBuilder
	var body: some MapContent {
		if !positions.isEmpty {
			nodeMap
		}
	}

	@MapContentBuilder
	var nodeMap: some MapContent {
		if showNodeHistory {
			history
		}

		latest
	}

	@MapContentBuilder
	private var latest: some MapContent {
		let latest = positions.filter { position in
			position.latest
		}.first

		if let latest = latest {
			let precision = PositionPrecision(rawValue: Int(latest.precisionBits))
			let radius: CLLocationDistance = precision?.precisionMeters ?? 0.0

			MapCircle(center: latest.coordinate, radius: max(30, radius))
				.foregroundStyle(
					Color(.black).opacity(0.5)
				)
				.stroke(.black.opacity(0.8), lineWidth: 5)

			Annotation(
				coordinate: latest.coordinate,
				anchor: .center
			) {
				Image(systemName: "flipphone")
					.font(.system(size: 32))
					.foregroundColor(node.color)
				.onTapGesture {
					selectedPosition = selectedPosition == latest ? nil : latest
				}
				.popover(item: $selectedPosition) { selection in
					PositionPopover(position: selection)
						.padding()
						.opacity(0.8)
						.presentationCompactAdaptation(.popover)
				}
			} label: { }
				.tag(latest.time)
				.annotationTitles(.automatic)
				.annotationSubtitles(.automatic)
		}
		else {
			EmptyMapContent()
		}
	}

	@MapContentBuilder
	private var history: some MapContent {
		let positionsFiltered = positions.filter { position in
			!position.latest
		}
		let coordinates = positionsFiltered.compactMap { position -> CLLocationCoordinate2D? in
			position.nodeCoordinate
		}
		let gradient = LinearGradient(
			colors: [
				node.color.opacity(0.50),
				node.color.opacity(0.10)
			],
			startPoint: .leading,
			endPoint: .trailing
		)
		let stroke = StrokeStyle(
			lineWidth: 5,
			lineCap: .round,
			lineJoin: .round
		)

		MapPolyline(coordinates: coordinates)
			.stroke(gradient, style: stroke)
	}

	private func getFlags(for position: PositionEntity) -> PositionFlags {
		let value = position.nodePosition?.metadata?.positionFlags ?? 771

		return PositionFlags(rawValue: Int(value))
	}
}
