//
//  TraceRouteDetail.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import SwiftData
import SwiftUI

/// One trace route: the hop timeline when it came back, otherwise what happened to the request,
/// with the round trip, hop counts and actions underneath.
struct TraceRouteDetail: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var router: Router
	@EnvironmentObject var accessoryManager: AccessoryManager

	let route: TraceRouteEntity

	@State private var selectedNodeNum: Int64?

	private var preset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	var body: some View {
		TimelineView(.periodic(from: .now, by: 10)) { timeline in
			let state = route.state(now: timeline.date)
			List {
				Section {
					TraceRouteCard(model: TraceRouteCardModel(route: route, title: title, now: timeline.date))
				}
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
				actions(state: state)
			}
		}
		.navigationTitle("Trace Route")
		.navigationBarTitleDisplayMode(.inline)
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

	@ViewBuilder
	private func actions(state: TraceRouteState) -> some View {
		Section {
			if route.hasPositions, state == .complete || state == .observed {
				Button {
					router.selectedTab = .map
					router.mapState = .traceRoute(route.id)
				} label: {
					Label("Show on Map", systemImage: "map")
				}
			}
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
			if !route.observed, accessoryManager.isConnected,
			   let target = route.node, target.num != accessoryManager.activeDeviceNum {
				TraceRouteButton(node: target)
			}
		}
	}
}
