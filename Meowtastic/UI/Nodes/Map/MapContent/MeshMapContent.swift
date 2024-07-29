import SwiftUI
import MapKit

struct MeshMapContent: MapContent {
	var delay: Double = 0

	@StateObject
	var appState = AppState.shared
	@Binding
	var showUserLocation: Bool
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

	@MapContentBuilder
	var body: some MapContent {
		ForEach(positions, id: \.id) { position in
			if
				let node = position.nodePosition,
				let nodeName = node.user?.shortName
			{
				Annotation(
					coordinate: position.coordinate,
					anchor: .center
				) {
					avatar(for: node, name: nodeName)
						.onTapGesture {
							selectedPosition = selectedPosition == position ? nil : position
						}
				} label: { }
					.tag(position.time)
					.annotationTitles(.automatic)
					.annotationSubtitles(.automatic)
			}
		}
	}

	@ViewBuilder
	private func avatar(for node: NodeInfoEntity, name: String) -> some View {
		ZStack(alignment: .top) {
			Avatar(
				name,
				temperature: temperature(for: node),
				background: color(for: node),
				size: 48
			)
			.padding(.all, 8)

			if node.hopsAway >= 0 {
				let color = color(for: node)
				if node.hopsAway == 0 {
					HStack(spacing: 0) {
						Spacer()
						Image(systemName: "wifi.circle.fill")
							.font(.system(size: 20))
							.background(color)
							.foregroundColor(color.isLight() ? .black.opacity(0.5) : .white.opacity(0.5))
							.clipShape(Circle())
					}
				}
				else {
					HStack(spacing: 0) {
						Spacer()
						Image(systemName: "\(node.hopsAway).circle.fill")
							.font(.system(size: 20))
							.background(color)
							.foregroundColor(color.isLight() ? .black.opacity(0.5) : .white.opacity(0.5))
							.clipShape(Circle())
					}
				}
			}
		}
		.frame(width: 64, height: 64)
	}

	private func temperature(for node: NodeInfoEntity) -> Double? {
		let nodeEnvironment = node
			.telemetries?
			.filtered(
				using: NSPredicate(format: "metricsType == 1")
			)
			.lastObject as? TelemetryEntity

		guard let temperature = nodeEnvironment?.temperature else {
			return nil
		}
		
		return Double(temperature)
	}

	private func color(for node: NodeInfoEntity) -> Color {
		if node.isOnline {
			return Color(
				UIColor(hex: UInt32(node.num))
			)
		}
		else {
			return Color.gray.opacity(0.7)
		}
	}
}
