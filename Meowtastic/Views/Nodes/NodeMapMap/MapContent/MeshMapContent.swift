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

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@State
	private var scale: CGFloat = 0.5

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "name", ascending: true)
		],
		predicate: NSPredicate(format: "enabled == true", ""),
		animation: .none
	)
	private var routes: FetchedResults<RouteEntity>

	@MapContentBuilder
	var body: some MapContent {
		ForEach(positions, id: \.id) { position in
			if let nodeName = position.nodePosition?.user?.shortName {
				Annotation(
					coordinate: position.coordinate,
					anchor: .center
				) {
					avatar(for: position, name: nodeName)
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

	@ViewBuilder
	private func avatar(for position: PositionEntity, name: String) -> some View {
		ZStack(alignment: .top) {
			Avatar(
				name,
				background: color(for: position),
				size: 48
			)
			.padding(.all, 8)

			if let hops = position.nodePosition?.hopsAway, hops >= 0 {
				if hops == 0 {
					HStack(spacing: 0) {
						Spacer()
						Image(systemName: "wifi.circle.fill")
							.font(.system(size: 20))
							.background(color(for: position))
							.foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.5))
							.clipShape(Circle())
					}
				}
				else {
					HStack(spacing: 0) {
						Spacer()
						Image(systemName: "\(hops).circle.fill")
							.font(.system(size: 20))
							.background(color(for: position))
							.foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.5))
							.clipShape(Circle())
					}
				}
			}
		}
		.frame(width: 64, height: 64)
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
