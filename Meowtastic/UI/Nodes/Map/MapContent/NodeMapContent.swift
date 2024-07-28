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
	var isMeshMap = false

	private let historyColor = Color.accentColor

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@AppStorage("meshMapShowNodeHistory")
	private var showNodeHistory = false
	@AppStorage("mapLayer")
	private var selectedMapLayer: MapLayer = .standard

	private var nodeColor: Color {
		if colorScheme == .dark {
			.white
		}
		else {
			.black
		}
	}

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

			MapCircle(center: latest.coordinate, radius: max(66.6, radius))
				.foregroundStyle(
					Color(nodeColor).opacity(0.25)
				)
				.stroke(nodeColor.opacity(0.5), lineWidth: 2)

			Annotation(
				coordinate: latest.coordinate,
				anchor: .center
			) {
				Image(systemName: "flipphone")
					.font(.system(size: 32))
					.foregroundColor(nodeColor)
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

		let gradientBackground = LinearGradient(
			colors: [
				nodeColor.opacity(0.30),
				nodeColor.opacity(0.20)
			],
			startPoint: .leading,
			endPoint: .trailing
		)
		let strokeBackground = StrokeStyle(
			lineWidth: 7,
			lineCap: .round,
			lineJoin: .round
		)

		let gradientMain = LinearGradient(
			colors: [
				historyColor.opacity(1.0),
				historyColor.opacity(0.5)
			],
			startPoint: .leading,
			endPoint: .trailing
		)
		let strokeMain = StrokeStyle(
			lineWidth: 3,
			lineCap: .round,
			lineJoin: .round
		)

		MapPolyline(coordinates: coordinates)
			.stroke(gradientBackground, style: strokeBackground)
		MapPolyline(coordinates: coordinates)
			.stroke(gradientMain, style: strokeMain)
	}

	private func getFlags(for position: PositionEntity) -> PositionFlags {
		let value = position.nodePosition?.metadata?.positionFlags ?? 771

		return PositionFlags(rawValue: Int(value))
	}
}
