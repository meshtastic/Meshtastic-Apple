//
//  SpatialMapWindow.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import CoreLocation
import OSLog
import SwiftData
import SwiftUI

/// Root of the spatial map volume. Owns the model and the scene, refreshes the node list every
/// couple of seconds, and closes with the main window like the Mesh Map window does.
struct SpatialMapWindow: View {
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var nodeFilters = NodeFilterParameters()
	@State private var model = SpatialMapModel()
	@State private var scene: SpatialSceneController
	@State private var traffic: SpatialTrafficController
	@AppStorage("mapLayer") private var mapLayer: MapLayer = .standard
	@AppStorage("enableMapPreciseLocationsOnly") private var preciseLocationsOnly = false
	@AppStorage("spatialMapDark") private var darkMap = true
	@AppStorage("spatialMapShowLabels") private var showLabels = true
	@AppStorage("spatialMapShowLinks") private var showLinks = true
	@AppStorage("spatialMapShowTraffic") private var showTraffic = true

	init() {
		let scene = SpatialSceneController()
		_scene = State(initialValue: scene)
		_traffic = State(initialValue: SpatialTrafficController(scene: scene))
	}

	private var preset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	private var refreshKey: String {
		"\(mapLayer.rawValue)|\(darkMap)|\(preciseLocationsOnly)|\(showLinks)|\(accessoryManager.activeDeviceNum ?? 0)|\(accessoryManager.isInBackground)"
	}

	var body: some View {
		SpatialMapView(model: model, scene: scene, traffic: traffic, preset: preset, showLinks: showLinks) { nodeNum in
			if let url = URL(string: "meshtastic:///nodes?nodenum=\(nodeNum)") {
				UIApplication.shared.open(url)
			}
		}
		.volumeBaseplateVisibility(.visible)
		.ornament(attachmentAnchor: .scene(.bottomFront)) {
			SpatialMapOrnament(
				model: model, traffic: traffic, mapLayer: $mapLayer, darkMap: $darkMap,
				showLabels: $showLabels, showLinks: $showLinks, showTraffic: $showTraffic
			)
		}
		.task(id: refreshKey) {
			guard !accessoryManager.isInBackground else { return }
			while !Task.isCancelled {
				refresh()
				try? await Task.sleep(for: .seconds(2))
			}
		}
		.onReceive(accessoryManager.packetEvents) { event in
			traffic.handle(event)
		}
		.onChange(of: accessoryManager.isHighMeshTraffic, initial: true) { _, isHigh in
			traffic.isHighTraffic = isHigh
		}
		.onChange(of: showTraffic, initial: true) { _, show in
			traffic.showPulses = show
			traffic.showGlow = show
		}
		.onChange(of: showLabels, initial: true) { _, show in
			model.showLabels = show
		}
		.onChange(of: appState.spatialMapFocus?.id) {
			claimFocus()
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .background {
				dismissWindow(id: SpatialMapScene.id)
			}
		}
		.onAppear {
			claimFocus()
			if !Self.mainWindowIsOpen {
				dismissWindow(id: SpatialMapScene.id)
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { _ in
			if !Self.mainWindowIsOpen {
				dismissWindow(id: SpatialMapScene.id)
			}
		}
		.trackScreen(.spatialMap)
	}

	private func refresh() {
		model.connectedNodeNum = accessoryManager.activeDeviceNum
		traffic.connectedNodeNum = accessoryManager.activeDeviceNum
		traffic.preset = preset
		model.showLinks = showLinks
		model.refresh(context: context, filters: nodeFilters, preciseOnly: preciseLocationsOnly, layer: mapLayer, dark: darkMap)
		// The distance filter measures from the connected radio.
		if let num = accessoryManager.activeDeviceNum, let coordinate = model.nodesByNum[num]?.coordinate {
			let current = nodeFilters.fallbackLocation
			if current == nil || abs(current!.latitude - coordinate.latitude) > 1e-7 || abs(current!.longitude - coordinate.longitude) > 1e-7 {
				nodeFilters.fallbackLocation = coordinate
			}
		}
	}

	private func claimFocus() {
		guard let nodeNum = appState.claimSpatialMapFocus() else { return }
		model.focus(on: nodeNum)
		refresh()
	}

	/// Any scene that is not one of the secondary windows.
	static var mainWindowIsOpen: Bool {
		UIApplication.shared.connectedScenes.contains {
			$0.activationState != .unattached
				&& $0.session.configuration.name != "meshmap-window"
				&& $0.session.configuration.name != SpatialMapScene.id
		}
	}
}

/// The volume's bottom toolbar: map layer, what to show, flyover, and the node count.
struct SpatialMapOrnament: View {
	let model: SpatialMapModel
	let traffic: SpatialTrafficController
	@Binding var mapLayer: MapLayer
	@Binding var darkMap: Bool
	@Binding var showLabels: Bool
	@Binding var showLinks: Bool
	@Binding var showTraffic: Bool

	var body: some View {
		HStack(spacing: 10) {
			Menu {
				Picker(String(localized: "Map Layer", comment: "Spatial map: picker for the image draped over the terrain"), selection: $mapLayer) {
					ForEach([MapLayer.standard, .hybrid, .satellite, .offline], id: \.self) { layer in
						Text(layer == .offline ? String(localized: "Terrain Shading", comment: "Spatial map layer: hillshade only, no map imagery") : layer.localized).tag(layer)
					}
				}
				Toggle(isOn: $darkMap) {
					Label(String(localized: "Dark Map", comment: "Spatial map: draw the map in its dark appearance"), systemImage: "moon")
				}
			} label: {
				Image(systemName: "map")
			}
			.accessibilityLabel(String(localized: "Map layer", comment: "VoiceOver label for the spatial map layer menu"))

			Toggle(isOn: $showLabels) { Image(systemName: "tag") }
				.accessibilityLabel(String(localized: "Node labels", comment: "VoiceOver label for the spatial map labels toggle"))
			Toggle(isOn: $showLinks) { Image(systemName: "point.3.connected.trianglepath.dotted") }
				.accessibilityLabel(String(localized: "Traceroute links", comment: "VoiceOver label for the spatial map links toggle"))
			Toggle(isOn: $showTraffic) { Image(systemName: "dot.radiowaves.left.and.right") }
				.accessibilityLabel(String(localized: "Live traffic", comment: "VoiceOver label for the spatial map traffic toggle"))

			if traffic.isFlying {
				Button {
					traffic.stopFlyover()
				} label: {
					Image(systemName: "stop.fill")
				}
				.accessibilityLabel(String(localized: "Stop flyover", comment: "VoiceOver label to stop the spatial map traceroute flyover"))
			} else {
				Menu {
					if model.routes.isEmpty {
						Text("No traceroutes with positions", comment: "Spatial map: flyover menu is empty")
					}
					ForEach(model.routes.prefix(12)) { route in
						Button {
							traffic.startFlyover(route)
						} label: {
							Text(verbatim: "\(route.targetName) · \(route.time?.formatted(date: .abbreviated, time: .shortened) ?? "")")
						}
					}
				} label: {
					Image(systemName: "airplane")
				}
				.accessibilityLabel(String(localized: "Fly a traceroute", comment: "VoiceOver label for the spatial map flyover menu"))
				.disabled(model.routes.isEmpty)
			}

			Divider().frame(height: 20)

			HStack(spacing: 6) {
				if model.isBuildingTerrain {
					ProgressView().controlSize(.small)
				}
				Text("\(model.nodes.count) nodes", comment: "Spatial map: how many nodes are on the terrain")
				if model.outsideCount > 0 {
					Text("· \(model.outsideCount) outside", comment: "Spatial map: nodes too far away to fit on the terrain")
						.foregroundStyle(.secondary)
				}
				if model.textureSource == .offline, mapLayer != .offline {
					Image(systemName: "wifi.slash")
						.foregroundStyle(.secondary)
						.help(String(localized: "Map imagery unavailable; showing terrain shading", comment: "Spatial map: the Apple map image could not be fetched"))
				}
			}
			.font(.caption)
		}
		.toggleStyle(.button)
		.buttonStyle(.borderless)
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
		.glassBackgroundEffect()
	}
}
#endif
