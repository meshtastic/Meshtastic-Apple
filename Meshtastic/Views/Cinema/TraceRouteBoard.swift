//
//  TraceRouteBoard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
#if os(visionOS)
import SwiftData
import SwiftUI

/// The latest trace route on the framed print by the tent's door in the cinema, drawn as the
/// app's own share card: the same route the trace route widget shows, requested or observed.
/// Tapping it shows the route on the front screen's map and flies it on the 3D map.
struct TraceRouteBoard: View {
	@EnvironmentObject private var appState: AppState
	@Environment(\.modelContext) private var context
	@Environment(\.openWindow) private var openWindow
	@State private var card: Card?
	/// False until the store has been read once, so the empty state doesn't flash first.
	@State private var loaded = false
	@State private var cardSize: CGSize = .zero

	/// The board's size in points. CinemaSpace scales the panel to the print in the image, so only
	/// the 1.1 × 0.9 m shape matters.
	static let size = CGSize(width: 1430, height: 1170)
	/// Strip of the print left showing around the card's background.
	private static let mat: CGFloat = 14
	/// Gap between the card's background and its content, so text doesn't touch the edge.
	private static let inset: CGFloat = 24
	/// How often the store is checked for a newer route. One small fetch; the card is only rebuilt
	/// when the route changes.
	private static let refreshInterval: Duration = .seconds(5)
	/// After a failed map snapshot the card is shown without a map, and the map is tried again
	/// after this long.
	private static let mapRetryInterval: TimeInterval = 5 * 60

	var body: some View {
		ZStack {
			if let card {
				Button {
					showRoute(card.routeId)
				} label: {
					cardView(card)
				}
				.buttonStyle(.plain)
				.hoverEffect(.highlight)
			} else if loaded {
				emptyState
			}
		}
		.frame(width: Self.size.width, height: Self.size.height)
		.background(PrintStyle.surface)
		.environment(\.colorScheme, .light)
		.task {
			while !Task.isCancelled {
				// The reset can start while this sleeps; don't read rows that are being deleted.
				if !appState.isDatabaseResetting {
					await refresh()
					loaded = true
				}
				try? await Task.sleep(for: Self.refreshInterval)
			}
		}
	}

	/// The card's background across the print, with the card's content at its own width scaled to
	/// fit inside it. The content goes without the card's own margin and minimum height, which would
	/// only leave more empty background around it here.
	private func cardView(_ card: Card) -> some View {
		ZStack {
			TraceRouteShareBackground(glowRadius: 460 * cardScale)
				.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			TraceRouteShareCard(model: card.model, mapImage: card.mapImage, framed: false)
				.environment(\.dynamicTypeSize, .large)
				.fixedSize()
				.onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
				.scaleEffect(cardScale)
				.opacity(cardSize == .zero ? 0 : 1)
		}
		.frame(width: Self.size.width - Self.mat * 2, height: Self.size.height - Self.mat * 2)
		.frame(width: Self.size.width, height: Self.size.height)
		.contentShape(Rectangle())
	}

	private var cardScale: CGFloat {
		guard cardSize.width > 0, cardSize.height > 0 else { return 1 }
		let margin = (Self.mat + Self.inset) * 2
		return min((Self.size.width - margin) / cardSize.width, (Self.size.height - margin) / cardSize.height)
	}

	private var emptyState: some View {
		VStack(spacing: 24) {
			Text("No trace routes yet", comment: "Cinema trace route board: shown when no trace route has come back yet")
				.font(.system(size: 76, weight: .bold))
				.foregroundStyle(PrintStyle.ink)
			Text("The latest trace route you send or hear shows here.", comment: "Cinema trace route board: what fills the empty board")
				.font(.system(size: 44))
				.foregroundStyle(PrintStyle.faded)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 1000)
		}
	}

	// MARK: Data

	/// The card for the route last read from the store.
	private struct Card {
		/// Changes when the route gets more hops or position snapshots, like the widget's.
		let key: String
		let routeId: Int64
		let model: TraceRouteShareModel
		let mapImage: UIImage?
		/// Set when the map snapshot failed; the map is tried again after this.
		let mapRetryAt: Date?
	}

	/// Reads the latest route, the same one the trace route widget shows, and rebuilds the card if
	/// it changed. The map tiles are drawn off the main thread, as for the share image.
	private func refresh() async {
		guard let route = WidgetTraceRouteRenderer.latestRoute(context: context) else {
			card = nil
			return
		}
		let key = "\(route.id)|\(route.hops.count)|\(route.nodePositions.count)"
		if let card, card.key == key {
			guard let retryAt = card.mapRetryAt, Date() >= retryAt else { return }
		}
		let preset = ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast
		let legs = TraceRouteLegs(route: route, preset: preset) { num in
			guard num != 0, num != TraceRouteLegs.unknownRepeaterNum else { return nil }
			return getNodeInfo(id: num, context: context).map(TraceRouteLegs.NodeDetails.init(node:))
		}
		let routeId = route.id
		let model = TraceRouteShareRenderer.fittingMap(TraceRouteShareModel(route: route, legs: legs, mapWidth: TraceRouteShareStyle.mapWidth))
		var mapImage: UIImage?
		if let map = model.map {
			mapImage = await TraceRouteShareRenderer.snapshot(rect: map.rect, size: map.size)
		}
		guard !Task.isCancelled else { return }
		let mapFailed = model.map != nil && mapImage == nil
		card = Card(
			key: key,
			routeId: routeId,
			model: model,
			mapImage: mapImage,
			mapRetryAt: mapFailed ? Date().addingTimeInterval(Self.mapRetryInterval) : nil
		)
	}

	/// Shows the route on the front screen's map, and asks the 3D map to fly it, opening the map if
	/// it was closed. Each takes its request as it appears.
	private func showRoute(_ routeId: Int64) {
		appState.cinemaScreenRequest = .traceRoute(routeId)
		appState.spatialMapRoute = SpatialMapRouteRequest(routeId: routeId)
		openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
	}
}

/// The print's mat, matching the blank print in the tent image, which has a light on it so it is
/// this light, and the ink for the empty board on it.
private enum PrintStyle {
	static let surface = LinearGradient(
		colors: [Color(red: 184 / 255, green: 164 / 255, blue: 134 / 255), Color(red: 170 / 255, green: 150 / 255, blue: 121 / 255)],
		startPoint: .top,
		endPoint: .bottom
	)
	static let ink = Color(red: 0.07, green: 0.07, blue: 0.08)
	static let faded = Color(red: 0.19, green: 0.18, blue: 0.17)
}
#endif
