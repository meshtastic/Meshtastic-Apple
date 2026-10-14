//
//  TraceRouteDetail.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import SwiftData
import SwiftUI

/// One trace route: the summary card, a row of actions, then the hop timeline when it came back
/// (otherwise what happened to the request) and the round trip and hop counts.
struct TraceRouteDetail: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var router: Router
	@EnvironmentObject var accessoryManager: AccessoryManager

	let route: TraceRouteEntity

	@State private var selectedNodeNum: Int64?
	@State private var shareImage: TraceRouteShareImage?
	@State private var isRenderingShareImage = false

	private var preset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	var body: some View {
		TraceRouteStateTimeline(route: route) { now in
			let state = route.state(now: now)
			List {
				Section {
					TraceRouteCard(model: TraceRouteCardModel(route: route, title: title, now: now))
						.contextMenu {
							if let shareImage {
								shareLink(shareImage)
							}
							copyButton
						}
				}
				actions(state: state)
				switch state {
				case .complete, .observed:
					Section {
						TraceRouteHopTimeline(
							legs: legs,
							canSelectStop: { num in num != accessoryManager.activeDeviceNum && findNode(num) != nil },
							onSelectStop: { selectedNodeNum = $0 }
						)
						.padding(.vertical, 8)
					}
				case .pending, .noResponse, .rateLimited:
					Section {
						stateMessage(state)
					}
				}
				details(state: state)
			}
		}
		.navigationTitle("Trace Route")
		.navigationBarTitleDisplayMode(.inline)
		.task(id: shareImageKey) {
			await renderShareImage()
		}
		.navigationDestination(item: $selectedNodeNum) { num in
			if let node = findNode(num) {
				NodeDetail(node: node, nodeNum: num)
			}
		}
	}

	private var targetName: String {
		route.node?.user?.longName ?? findNode(route.toNum)?.user?.longName ?? route.toNum.toHex()
	}

	private var title: String {
		let origin = findNode(route.fromNum)?.user?.longName ?? route.fromNum.toHex()
		return "\(origin) → \(targetName)"
	}

	private var legs: TraceRouteLegs {
		TraceRouteLegs(route: route, preset: preset) { num in
			findNode(num).map(TraceRouteLegs.NodeDetails.init(node:))
		}
	}

	/// Changes when the route gets its response or position snapshots, so the image is redrawn.
	private var shareImageKey: String {
		"\(route.id)|\(route.response)|\(route.nodePositions.count)"
	}

	private func renderShareImage() async {
		let state = route.state()
		guard state == .complete || state == .observed else {
			shareImage = nil
			return
		}
		isRenderingShareImage = true
		defer { isRenderingShareImage = false }
		let model = TraceRouteShareModel(route: route, legs: legs, mapWidth: TraceRouteShareStyle.mapWidth)
		shareImage = await TraceRouteShareRenderer.render(model: model)
	}

	private func shareLink(_ image: TraceRouteShareImage) -> some View {
		ShareLink(
			item: image,
			subject: Text(image.title),
			preview: SharePreview(image.title, image: Image(uiImage: image.image))
		) {
			Label("Share", systemImage: "square.and.arrow.up")
		}
	}

	private func findNode(_ num: Int64) -> NodeInfoEntity? {
		guard num != 0, num != TraceRouteLegs.unknownRepeaterNum else { return nil }
		return router.cachedNodeInfo(id: num, context: context)
	}

	@ViewBuilder
	private func stateMessage(_ state: TraceRouteState) -> some View {
		switch state {
		case .rateLimited:
			VStack(alignment: .leading, spacing: 6) {
				Text("Trace route to \(targetName) was not sent.")
					.font(.headline)
				Text("Trace Route was rate limited. You can send a trace route a maximum of once every thirty seconds.")
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		default:
			VStack(alignment: .leading, spacing: 6) {
				Text("Trace route sent to \(targetName)")
					.font(.headline)
				if state == .noResponse {
					Text("A Trace Route was sent, no response has been received.")
						.font(.callout)
						.foregroundStyle(.secondary)
				} else {
					Text("This could take a while, response will appear in the trace route log for the node it was sent to.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	@ViewBuilder
	private func details(state: TraceRouteState) -> some View {
		if state == .complete || state == .observed {
			Section {
				if let roundTrip = route.roundTrip {
					LabeledContent(String(localized: "Round trip", comment: "Trace route: time from sending the request to getting the response")) {
						Text(TraceRouteCardModel.formattedRoundTrip(roundTrip))
					}
				}
				LabeledContent(String(localized: "Forward hops", comment: "Trace route: hop count towards the target")) {
					Text(TraceRouteCardModel.hops(Int(route.hopsTowards)))
				}
				if route.hopsBack >= 0 {
					LabeledContent(String(localized: "Return hops", comment: "Trace route: hop count on the way back")) {
						Text(TraceRouteCardModel.hops(Int(route.hopsBack)))
					}
				}
				if let time = route.time {
					LabeledContent("Time") {
						Text(time.formatted(date: .abbreviated, time: .standard))
					}
				}
			}
		}
	}

	/// Map, Share and Trace Route as one row of equal buttons between the card and the route.
	@ViewBuilder
	private func actions(state: TraceRouteState) -> some View {
		let answered = state == .complete || state == .observed
		let canMap = route.hasPositions && answered
		let target = route.node
		let canTrace = !route.observed && accessoryManager.isConnected && target != nil && target?.num != accessoryManager.activeDeviceNum
		if canMap || answered || canTrace {
			Section {
				HStack(spacing: 10) {
					if canMap {
						Button {
							router.selectedTab = .map
							router.mapState = .traceRoute(route.id)
						} label: {
							TraceRouteActionLabel(title: String(localized: "Map", comment: "Trace route detail: button that shows the route on the map"), systemImage: "map")
						}
					}
					if answered {
						if let shareImage {
							ShareLink(
								item: shareImage,
								subject: Text(shareImage.title),
								preview: SharePreview(shareImage.title, image: Image(uiImage: shareImage.image))
							) {
								TraceRouteActionLabel(title: String(localized: "Share", comment: "Trace route detail: share the route image"), systemImage: "square.and.arrow.up")
							}
						} else {
							TraceRouteActionLabel(title: String(localized: "Share", comment: "Trace route detail: share the route image"), systemImage: "square.and.arrow.up", isBusy: isRenderingShareImage)
								.foregroundStyle(.secondary)
						}
					}
					if canTrace, let target {
						TraceRouteButton(node: target, compact: true)
					}
				}
				.buttonStyle(.borderless)
				.listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
				.listRowBackground(Color.clear)
			}
		}
	}

	@ViewBuilder
	private var copyButton: some View {
		if let routeText = route.routeText {
			Button {
				var text = String(localized: "Route: \(routeText)")
				if let back = route.routeBackText {
					text += "\n" + String(localized: "Route Back: \(back)")
				}
				UIPasteboard.general.string = text
			} label: {
				Label("Copy", systemImage: "doc.on.doc")
			}
		}
	}
}

/// One of the equal-width action tiles in the trace route detail: an icon over a short title.
struct TraceRouteActionLabel: View {
	let title: String
	let systemImage: String
	var isBusy = false

	var body: some View {
		VStack(spacing: 6) {
			if isBusy {
				ProgressView()
					.frame(height: 22)
			} else {
				Image(systemName: systemImage)
					.font(.title3)
					.frame(height: 22)
			}
			Text(title)
				.font(.caption.weight(.semibold))
				.lineLimit(1)
				.minimumScaleFactor(0.8)
		}
		.frame(maxWidth: .infinity, minHeight: 64)
		.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
}
