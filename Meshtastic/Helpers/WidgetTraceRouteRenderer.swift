//
//  WidgetTraceRouteRenderer.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  Renders the trace route widget's map from the most recent trace route,
//  requested or observed. It reuses the share image: the same model and the
//  same map view, sized for the widget — a square for small and medium, a
//  wide one for large. The route's details go to the store as plain values so
//  the widget lays them out itself and its times keep aging.
//

import MapKit
import OSLog
import SwiftData
import SwiftUI
import WidgetKit

@MainActor
final class WidgetTraceRouteRenderer {
	static let shared = WidgetTraceRouteRenderer()

	static let kind = "MeshTraceRoute"
	/// Square map for small and medium, in points.
	private static let squareSize = CGSize(width: 170, height: 170)
	/// Wide map for large, in points.
	private static let wideSize = CGSize(width: 330, height: 190)
	/// The widget's render scale; tiles are snapshotted at the same scale so
	/// they aren't stretched.
	private static let scale: CGFloat = 3
	/// Hop badges are 16 points; keep them at least this far apart on the
	/// small maps.
	private static let minimumBadgeGap: CGFloat = 18
	/// Observed routes can arrive often on a busy mesh, so they redraw at most
	/// this often. A route we requested is always shown right away.
	private static let observedInterval: TimeInterval = 15 * 60
	/// After a failed map snapshot the details are shown without a map, and the
	/// map is tried again after this long.
	private static let mapRetryInterval: TimeInterval = 5 * 60
	private static let noRouteKey = "none"

	private enum Outcome {
		case saved
		/// The details were saved without a map because the snapshot failed.
		case savedWithoutMap
		case failed
	}

	/// The route last written to the store.
	private var lastSavedKey: String?
	/// Set when that route was written without its map; the map is retried.
	private var mapRetryAt: Date?
	/// When an observed route was last written, for the observed interval.
	private var lastObservedSaveAt: Date?
	private var inFlightKey: String?
	private var renderTask: Task<Void, Never>?
	/// A refresh held back by the observed interval, run when it lapses so a
	/// newer observed route isn't lost if nothing else triggers a refresh.
	private var deferredRefresh: Task<Void, Never>?

	/// Called after a trace route is saved, and by the widget broker so a fresh
	/// install or launch catches up. Cheap when nothing changed: one small fetch.
	func refresh() {
		guard !PersistenceController.shared.isProvisionalPendingFirstUnlock else { return }
		let context = PersistenceController.shared.context
		guard let route = Self.latestRoute(context: context) else {
			clearIfNeeded()
			return
		}

		// Changes when the route gets its response, more hops or position snapshots.
		let key = "\(route.id)|\(route.hops.count)|\(route.nodePositions.count)"
		guard key != inFlightKey else { return }
		if key == lastSavedKey {
			// Already shown; only a map that failed to draw is worth another try.
			guard let mapRetryAt, Date() >= mapRetryAt else { return }
		} else if route.observed, let lastObservedSaveAt {
			let elapsed = Date().timeIntervalSince(lastObservedSaveAt)
			if elapsed < Self.observedInterval {
				scheduleDeferredRefresh(after: Self.observedInterval - elapsed)
				return
			}
		}

		let preset = ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast
		let legs = TraceRouteLegs(route: route, preset: preset) { num in
			guard num != 0, num != TraceRouteLegs.unknownRepeaterNum else { return nil }
			return getNodeInfo(id: num, context: context).map(TraceRouteLegs.NodeDetails.init(node:))
		}
		let positions = route.nodePositionsByNum.compactMapValues { $0.coordinate }
		let square = Self.model(route: route, legs: legs, positions: positions, size: Self.squareSize)
		let wide = Self.model(route: route, legs: legs, positions: positions, size: Self.wideSize)
		let details = Self.details(route: route, model: square)
		let observed = route.observed

		inFlightKey = key
		renderTask?.cancel()
		renderTask = Task {
			let outcome = await Self.render(details: details, square: square, wide: wide)
			// A superseded render must not commit state for the older route.
			if !Task.isCancelled {
				switch outcome {
				case .saved:
					self.lastSavedKey = key
					self.mapRetryAt = nil
				case .savedWithoutMap:
					self.lastSavedKey = key
					self.mapRetryAt = Date().addingTimeInterval(Self.mapRetryInterval)
				case .failed:
					break
				}
				if outcome != .failed, observed {
					self.lastObservedSaveAt = Date()
				}
			}
			if self.inFlightKey == key {
				self.inFlightKey = nil
			}
		}
	}

	/// No route left to show — the radio was switched, app data cleared or the
	/// log emptied — so the widget must not keep showing a deleted route.
	private func clearIfNeeded() {
		guard lastSavedKey != Self.noRouteKey else { return }
		renderTask?.cancel()
		// Cleared here, not in the cancelled task: a handle left set would make
		// every later deferral look already scheduled.
		deferredRefresh?.cancel()
		deferredRefresh = nil
		inFlightKey = nil
		if WidgetTraceRouteStore.load() != nil {
			WidgetTraceRouteStore.clear()
			WidgetCenter.shared.reloadTimelines(ofKind: Self.kind)
		}
		lastSavedKey = Self.noRouteKey
		mapRetryAt = nil
	}

	private func scheduleDeferredRefresh(after delay: TimeInterval) {
		guard deferredRefresh == nil else { return }
		deferredRefresh = Task { [weak self] in
			try? await Task.sleep(for: .seconds(delay))
			// A cancelled task leaves the property alone; whoever cancelled it
			// already cleared it, and it may hold a newer task by now.
			guard let self, !Task.isCancelled else { return }
			self.deferredRefresh = nil
			self.refresh()
		}
	}

	/// The newest route that came back: requested and answered, or observed.
	/// `response` is a scalar, so the predicate is safe; rate-limited and
	/// pending records are skipped in Swift by `state()`. The cinema's trace
	/// route board shows the same one.
	static func latestRoute(context: ModelContext) -> TraceRouteEntity? {
		var descriptor = FetchDescriptor<TraceRouteEntity>(
			predicate: #Predicate { $0.response == true },
			sortBy: [SortDescriptor(\.time, order: .reverse)]
		)
		descriptor.fetchLimit = 5
		let routes = (try? context.fetch(descriptor)) ?? []
		return routes.first { route in
			let state = route.state()
			return state == .complete || state == .observed
		}
	}

	private static func model(
		route: TraceRouteEntity, legs: TraceRouteLegs, positions: [Int64: CLLocationCoordinate2D], size: CGSize
	) -> TraceRouteShareModel {
		TraceRouteShareModel(
			legs: legs,
			positions: positions,
			date: route.time,
			observed: route.observed,
			roundTrip: route.roundTrip,
			mapWidth: size.width,
			mapHeight: size.height
		)
	}

	private static func details(route: TraceRouteEntity, model: TraceRouteShareModel) -> WidgetTraceRoute {
		func stops(_ list: [TraceRouteStop]) -> [WidgetTraceRoute.Stop] {
			list.map {
				WidgetTraceRoute.Stop(
					num: $0.num,
					shortName: $0.shortName,
					longName: $0.longName,
					isUnknownRepeater: $0.isUnknownRepeater,
					viaMqtt: $0.viaMqtt
				)
			}
		}
		return WidgetTraceRoute(
			generatedAt: Date(),
			routeId: route.id,
			time: route.time,
			observed: route.observed,
			forward: stops(model.legs.forward),
			back: stops(model.legs.back),
			roundTrip: model.roundTrip,
			distance: model.routeDistance,
			bestSNR: model.bestLeg?.snr,
			worstSNR: model.worstLeg?.snr,
			hasMap: model.map != nil
		)
	}

	private static func render(details: WidgetTraceRoute, square: TraceRouteShareModel, wide: TraceRouteShareModel) async -> Outcome {
		guard details.hasMap, let squareFrame = square.map, let wideFrame = wide.map else {
			return save(details, square: nil, wide: nil) ? .saved : .failed
		}
		// The share image's dark, muted tiles, so the widget matches it.
		let squareTiles = await TraceRouteShareRenderer.snapshot(rect: squareFrame.rect, size: squareFrame.size, scale: scale)
		let wideTiles = await TraceRouteShareRenderer.snapshot(rect: wideFrame.rect, size: wideFrame.size, scale: scale)
		guard !Task.isCancelled else { return .failed }
		guard let squareTiles, let wideTiles,
			  let squareData = drawMap(frame: squareFrame, tiles: squareTiles, legs: square.legs)?.pngData(),
			  let wideData = drawMap(frame: wideFrame, tiles: wideTiles, legs: wide.legs)?.pngData() else {
			// Offline or a snapshotter error: show the new route's details now,
			// like the share image leaves out a map it couldn't load.
			Logger.services.warning("🧩 Widget trace route map render failed; saving the details without a map.")
			var withoutMap = details
			withoutMap.hasMap = false
			return save(withoutMap, square: nil, wide: nil) ? .savedWithoutMap : .failed
		}
		return save(details, square: squareData, wide: wideData) ? .saved : .failed
	}

	private static func save(_ details: WidgetTraceRoute, square: Data?, wide: Data?) -> Bool {
		guard WidgetTraceRouteStore.save(route: details, squareImage: square, wideImage: wide) else { return false }
		WidgetCenter.shared.reloadTimelines(ofKind: kind)
		return true
	}

	/// The share card's map view — route lines, hop badges, SNR labels and
	/// endpoint circles over the tiles — drawn to an image.
	private static func drawMap(frame: TraceRouteShareModel.MapFrame, tiles: UIImage, legs: TraceRouteLegs) -> UIImage? {
		let renderer = ImageRenderer(content: TraceRouteShareMap(
			frame: frame,
			image: tiles,
			legs: legs,
			minimumBadgeGap: minimumBadgeGap
		)
		.environment(\.colorScheme, .dark)
		.environment(\.dynamicTypeSize, .large))
		renderer.scale = scale
		renderer.proposedSize = ProposedViewSize(frame.size)
		return renderer.uiImage
	}
}
