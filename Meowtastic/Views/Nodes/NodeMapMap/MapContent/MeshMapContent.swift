import SwiftUI
import MapKit

struct MeshMapContent: MapContent {
	var delay: Double = 0

	@StateObject
	var appState = AppState.shared
	@Binding
	var showUserLocation: Bool
	@Binding
	var selectedMapLayer: MapLayer
	@Binding
	var selectedPosition: PositionEntity?

	@FetchRequest(
		fetchRequest: PositionEntity.allPositionsFetchRequest(),
		animation: .easeIn
	)
	var positions: FetchedResults<PositionEntity>

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "name", ascending: true)
		],
		predicate: NSPredicate(format: "enabled == true", ""),
		animation: .none
	)
	private var routes: FetchedResults<RouteEntity>

	@State
	private var scale: CGFloat = 0.5

	@MapContentBuilder
	var body: some MapContent {
		ForEach(positions, id: \.id) { position in
			if let nodeName = position.nodePosition?.user?.shortName {
				Annotation(
					coordinate: position.coordinate,
					anchor: .center
				) {
					Avatar(nodeName, background: color(for: position))
						.font(.system(size: 32))
						.onTapGesture { location in
							selectedPosition = (selectedPosition == position ? nil : position)
						}
						.popover(item: $selectedPosition) { selection in
							PositionPopover(position: selection)
								.padding()
								.opacity(0.8)
								.presentationCompactAdaptation(.popover)
						}
				} label: { }
					.tag(position.time)
					.annotationTitles(.automatic)
					.annotationSubtitles(.automatic)
			}
		}
	}

	private func color(for position: PositionEntity) -> Color {
		if let isOnline = position.nodePosition?.isOnline, isOnline {
			return Color(
				UIColor(hex: UInt32(position.nodePosition?.num ?? 0))
			)
		}
		else {
			return Color.gray.opacity(0.7)
		}
	}
}
