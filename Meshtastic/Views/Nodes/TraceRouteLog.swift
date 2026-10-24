//
//  TraceRouteLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/7/23.
//

import Foundation
import SwiftUI
import SwiftData
import OSLog

struct TraceRouteLog: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Bindable var node: NodeInfoEntity
	@State private var traceRoutes: [TraceRouteEntity] = []
	/// Chart points for the visible routes, rebuilt when the routes or the window change rather than on every redraw.
	@State private var chartPoints: [TraceRouteChartPoint] = []
	/// The route picked on the chart, highlighted in the list.
	@State private var highlightedID: Int64?
	@State private var openRouteID: PersistentIdentifier?
	@SceneStorage("traceRouteLogWindow") private var windowRawValue = TraceRouteTimeWindow.day.rawValue
	@SceneStorage("traceRouteLogChartExpanded") private var chartExpanded = true

	private var availableWindows: [TraceRouteTimeWindow] {
		TraceRouteTimeWindow.available(oldest: traceRoutes.compactMap { $0.time ?? $0.sentAt }.min())
	}

	/// The stored window, or `all` when the log no longer reaches back past it.
	private var window: TraceRouteTimeWindow {
		let stored = TraceRouteTimeWindow(rawValue: windowRawValue) ?? .all
		return availableWindows.contains(stored) ? stored : .all
	}

	private var visibleRoutes: [TraceRouteEntity] {
		let window = window
		return traceRoutes.filter { window.contains($0.time ?? $0.sentAt) }
	}

	private var canTrace: Bool {
		accessoryManager.isConnected && node.num != accessoryManager.activeDeviceNum
	}

	var body: some View {
		ScrollViewReader { proxy in
			List {
				if canTrace {
					Section {
						TraceRouteButton(node: node)
					}
				}
				if traceRoutes.isEmpty {
					ContentUnavailableView("No Trace Routes", systemImage: "signpost.right.and.left")
				} else {
					header
					Section {
						ForEach(visibleRoutes, id: \.persistentModelID) { route in
							TraceRouteStateTimeline(route: route) { now in
								Button {
									openRouteID = route.persistentModelID
								} label: {
									TraceRouteCard(model: TraceRouteCardModel(route: route, now: now))
										.contentShape(Rectangle())
								}
								.buttonStyle(.plain)
							}
							.id(route.id)
							.listRowBackground(route.id == highlightedID ? Color.accentColor.opacity(0.15) : nil)
							.swipeActions {
								Button(role: .destructive) {
									delete(route)
								} label: {
									Label("Delete", systemImage: "trash")
								}
							}
						}
					}
				}
			}
			.onChange(of: windowRawValue) { rebuildChartPoints() }
			.onChange(of: highlightedID) { _, id in
				guard let id else { return }
				withAnimation { proxy.scrollTo(id, anchor: .center) }
			}
		}
		.task { refreshTraceRoutes() }
		.onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
			if Self.touchesTraceRoutes(notification) { refreshTraceRoutes() }
		}
		.navigationTitle("Trace Route Log")
		.navigationDestination(item: $openRouteID) { id in
			if let route = traceRoutes.first(where: { $0.persistentModelID == id }) {
				TraceRouteDetail(route: route)
			}
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
	}

	@ViewBuilder
	private var header: some View {
		let windows = availableWindows
		if windows.count > 1 {
			Section {
				Picker(String(localized: "Time window", comment: "Trace route log: how far back the chart and list go"), selection: Binding(
					get: { window.rawValue },
					set: { windowRawValue = $0 }
				)) {
					ForEach(windows) { window in
						Text(window.label).tag(window.rawValue)
					}
				}
				.pickerStyle(.segmented)
				.listRowBackground(Color.clear)
				.listRowInsets(EdgeInsets())
			}
		}
		let points = chartPoints
		if !points.isEmpty {
			Section {
				DisclosureGroup(isExpanded: $chartExpanded) {
					TraceRouteChart(points: points, selectedID: $highlightedID)
						.padding(.vertical, 8)
				} label: {
					Label("Hops", systemImage: "chart.xyaxis.line")
				}
			}
		}
	}

	/// Loads the routes once and again only after a trace route is saved. The database is read here,
	/// not while the view draws, so a busy mesh saving packets doesn't re-run the fetch.
	private func refreshTraceRoutes() {
		traceRoutes = node.safeTraceRoutes()
		if let openRouteID, !traceRoutes.contains(where: { $0.persistentModelID == openRouteID }) {
			self.openRouteID = nil
		}
		rebuildChartPoints()
	}

	private func rebuildChartPoints() {
		chartPoints = TraceRouteChartPoint.points(from: visibleRoutes.map { (id: $0.id, card: TraceRouteCardModel(route: $0)) })
	}

	private static func touchesTraceRoutes(_ notification: Foundation.Notification) -> Bool {
		(notification.userInfo ?? [:]).values.contains { value in
			(value as? Set<PersistentIdentifier>)?.contains { $0.entityName == "TraceRouteEntity" } ?? false
		}
	}

	private func delete(_ route: TraceRouteEntity) {
		if highlightedID == route.id {
			highlightedID = nil
		}
		if openRouteID == route.persistentModelID {
			openRouteID = nil
		}
		context.delete(route)
		do {
			try context.save()
			refreshTraceRoutes()
		} catch let error as NSError {
			Logger.data.error("\(error.localizedDescription, privacy: .public)")
		}
	}
}
