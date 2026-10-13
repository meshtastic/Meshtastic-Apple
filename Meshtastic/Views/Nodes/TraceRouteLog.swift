//
//  TraceRouteLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/7/23.
//

import SwiftUI
import SwiftData
import OSLog

struct TraceRouteLog: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.modelContext) private var context
	@EnvironmentObject var router: Router
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Bindable var node: NodeInfoEntity
	@State private var traceRoutes: [TraceRouteEntity] = []
	@State private var selectedRouteID: PersistentIdentifier?

	private var selectedRoute: TraceRouteEntity? {
		guard let selectedRouteID else { return nil }
		return traceRoutes.first { $0.persistentModelID == selectedRouteID }
	}

	var body: some View {
		HStack(alignment: .top) {
			VStack {
				VStack {
					List(traceRoutes, id: \.persistentModelID, selection: $selectedRouteID) { route in
						TraceRouteStateTimeline(route: route) { now in
							row(for: route, now: now)
						}
						.swipeActions {
							Button(role: .destructive) {
								if selectedRouteID == route.persistentModelID {
									selectedRouteID = nil
								}
								context.delete(route)
								do {
									try context.save()
									refreshTraceRoutes()
								} catch let error as NSError {
									Logger.data.error("\(error.localizedDescription, privacy: .public)")
								}
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
					.listStyle(.plain)
				}
				Divider()
				ScrollView {
					if selectedRoute != nil {
						let selectedState = selectedRoute?.state()
						if selectedState == .complete || selectedState == .observed {
							let routeValue = selectedRoute?.routeText ?? "Unknown".localized
							let routeBackValue = selectedRoute?.routeBackText ?? "Unknown".localized
							Label {
								Text("Route: \(routeValue)")
									.textSelection(.enabled)
							} icon: {
								Image(systemName: "signpost.right")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title3)
							.contextMenu {
								Button {
									UIPasteboard.general.string = String(localized: "Route: \(routeValue)")
								} label: {
									Label("Copy", systemImage: "doc.on.doc")
								}
							}
							Label {
								Text("Route Back: \(routeBackValue)")
									.textSelection(.enabled)
							} icon: {
								Image(systemName: "signpost.left")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title3)
							.contextMenu {
								Button {
									UIPasteboard.general.string = String(localized: "Route Back: \(routeBackValue)")
								} label: {
									Label("Copy", systemImage: "doc.on.doc")
								}
							}
							if selectedRoute?.hasPositions ?? false, let routeID = selectedRoute?.id {
								Button {
									router.selectedTab = .map
									router.mapState = .traceRoute(routeID)
								} label: {
									Label("Show on Map", systemImage: "map")
								}
								.buttonStyle(.bordered)
								.padding(.top, 4)
							}
						} else if selectedState == .rateLimited {
							Label {
								VStack {
									Text("Trace route to \(selectedRoute?.node?.user?.longName ?? "Unknown".localized) was not sent.")
										.font(idiom == .phone ? .body : .largeTitle)
										.fontWeight(.semibold)
									Text("Trace Route was rate limited. You can send a trace route a maximum of once every thirty seconds.")
										.font(idiom == .phone ? .caption : .body)
										.foregroundStyle(.secondary)
										.padding()
								}
							} icon: {
								Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
									.symbolRenderingMode(.hierarchical)
							}
						} else {
							Label {
								VStack {
									Text("Trace route sent to \(selectedRoute?.node?.user?.longName ?? "Unknown".localized)")
										.font(idiom == .phone ? .body : .largeTitle)
										.fontWeight(.semibold)
									Text("A Trace Route was sent, no response has been received.")
										.font(idiom == .phone ? .caption : .body)
										.foregroundStyle(.secondary)
										.padding()
								}
							} icon: {
								Image(systemName: "signpost.right.and.left")
									.symbolRenderingMode(.hierarchical)
							}
						}
						Spacer()
							.padding(.bottom, 125)
					} else {
						ContentUnavailableView("Select a Trace Route", systemImage: "signpost.right.and.left")
					}
				}
				.edgesIgnoringSafeArea(.bottom)
			}
			.navigationTitle("Trace Route Log")
		}
		.onAppear {
			refreshTraceRoutes()
		}
		.onChange(of: node.lastHeard) {
			refreshTraceRoutes()
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
	}

	private func refreshTraceRoutes() {
		traceRoutes = node.safeTraceRoutes()
		if let selectedRouteID, !traceRoutes.contains(where: { $0.persistentModelID == selectedRouteID }) {
			self.selectedRouteID = nil
		}
	}

	@ViewBuilder
	private func row(for route: TraceRouteEntity, now: Date) -> some View {
		let state = route.state(now: now)
		Label {
			let routeTime = route.time?.formatted(date: .numeric, time: .shortened) ?? "Unknown".localized
			if let stateLabel = state.label {
				Text("\(routeTime) - \(stateLabel)")
					.font(.caption)
			} else if route.hopsTowards == route.hopsBack {
				let hopString = String(localized: "\(route.hopsTowards) Hops")
				Text("\(routeTime) - \(hopString)")
					.font(.caption)
			} else {
				let hopTowardsString = String(localized: "\(route.hopsTowards) Hops")
				let hopBackString = route.hopsBack >= 0 ? String(localized: "\(route.hopsBack) Hops") : String(localized: "Unknown")
				Text("\(routeTime) - \(hopTowardsString) Towards  \(hopBackString) Back")
					.font(.caption)
			}
		} icon: {
			Image(systemName: route.rowSystemImage(now: now))
				.symbolRenderingMode(.hierarchical)
		}
	}
}

// TODO: Fix preview for SwiftData
/*
#Preview {
	let node = NodeInfoEntity()
	node.num = 123456789
	let user = UserEntity()
	user.longName = "Test Node"
	user.shortName = "TN"
	node.user = user
	TraceRouteLog(node: node)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
*/
