//
//  AllTraceRoutesLog.swift
//  Meshtastic
//
//  App-wide log of every trace route response we have seen — both routes we initiated
//  and full responses observed passing over the mesh.
//

import SwiftUI
import SwiftData
import OSLog

struct AllTraceRoutesLog: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.modelContext) private var context
	@EnvironmentObject var router: Router
	@EnvironmentObject var accessoryManager: AccessoryManager

	@Query(sort: \TraceRouteEntity.time, order: .reverse)
	private var traceRoutes: [TraceRouteEntity]
	@Query private var nodes: [NodeInfoEntity]

	@State private var selectedRouteID: PersistentIdentifier?

	private var modemPreset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast }

	private var nodeNames: [Int64: String] {
		Dictionary(nodes.map { ($0.num, $0.user?.longName ?? $0.num.toHex()) }, uniquingKeysWith: { first, _ in first })
	}

	private var selectedRoute: TraceRouteEntity? {
		guard let selectedRouteID else { return nil }
		return traceRoutes.first { $0.persistentModelID == selectedRouteID }
	}

	private func name(for num: Int64) -> String {
		nodeNames[num] ?? num.toHex()
	}

	var body: some View {
		HStack(alignment: .top) {
			VStack {
				if traceRoutes.isEmpty {
					ContentUnavailableView("No Trace Routes", systemImage: "point.3.connected.trianglepath.dotted")
				} else {
					List(traceRoutes, id: \.persistentModelID, selection: $selectedRouteID) { route in
						Label {
							VStack(alignment: .leading, spacing: 2) {
								Text("\(name(for: route.fromNum)) → \(name(for: route.toNum))")
									.font(.callout)
									.fontWeight(.medium)
								let routeTime = route.time?.formatted(date: .numeric, time: .shortened) ?? "Unknown".localized
								let hopTowards = String(localized: "\(route.hopsTowards) Hops")
								let hopBack = route.hopsBack >= 0 ? String(localized: "\(route.hopsBack) Hops") : "Unknown".localized
								Text("\(routeTime) • \(hopTowards) Towards • \(hopBack) Back")
									.font(.caption)
									.foregroundStyle(.secondary)
								Text(route.observed ? "Observed" : "Requested")
									.font(.caption2)
									.foregroundStyle(route.observed ? Color.orange : Color.accentColor)
							}
						} icon: {
							Image(systemName: route.hopsTowards == 0 ? "person.line.dotted.person" : "point.3.connected.trianglepath.dotted")
								.symbolRenderingMode(.hierarchical)
						}
						.swipeActions {
							Button(role: .destructive) {
								delete(route)
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
					.listStyle(.plain)
				}
				Divider()
				ScrollView {
					if let selectedRoute {
						detail(for: selectedRoute)
							.padding(.horizontal)
					} else {
						ContentUnavailableView("Select a Trace Route", systemImage: "signpost.right.and.left")
					}
				}
			}
			.navigationTitle("Trace Routes")
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
	}

	@ViewBuilder
	private func detail(for route: TraceRouteEntity) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Label {
				Text("Route: \(route.routeText ?? "Unknown".localized)")
			} icon: {
				Image(systemName: "signpost.right")
					.symbolRenderingMode(.hierarchical)
			}
			.font(.title3)
			Label {
				Text("Route Back: \(route.routeBackText ?? "Unknown".localized)")
			} icon: {
				Image(systemName: "signpost.left")
					.symbolRenderingMode(.hierarchical)
			}
			.font(.title3)
			if route.hasPositions {
				Button {
					router.selectedTab = .map
					router.mapState = .traceRoute(route.id)
				} label: {
					Label("Show on Map", systemImage: "map")
				}
				.buttonStyle(.bordered)
				.padding(.top, 4)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical)
	}

	private func delete(_ route: TraceRouteEntity) {
		if selectedRouteID == route.persistentModelID {
			selectedRouteID = nil
		}
		context.delete(route)
		do {
			try context.save()
		} catch let error as NSError {
			Logger.data.error("\(error.localizedDescription, privacy: .public)")
		}
	}
}
