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
	@Environment(\.physicalMetrics) private var metrics
	@StateObject private var nodeFilters = NodeFilterParameters()
	@State private var model = SpatialMapModel()
	@State private var scene: SpatialSceneController
	@State private var traffic: SpatialTrafficController
	@AppStorage("mapLayer") private var mapLayer: MapLayer = .standard
	@AppStorage("enableMapPreciseLocationsOnly") private var preciseLocationsOnly = false
	@AppStorage("spatialMapDark") private var darkMap = true
	/// Shared with the 2D map's Contour Lines setting.
	@AppStorage("meshMapShowContours") private var showContours = false
	@AppStorage("spatialMapShowLabels") private var showLabels = true
	@AppStorage("spatialMapShowLinks") private var showLinks = true
	@AppStorage("spatialMapShowTraffic") private var showTraffic = true
	@AppStorage("spatialMapAutoTerrain") private var autoTerrain = true

	init() {
		let scene = SpatialSceneController()
		_scene = State(initialValue: scene)
		_traffic = State(initialValue: SpatialTrafficController(scene: scene))
	}

	private var preset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	private var refreshKey: String {
		"\(mapLayer.rawValue)|\(darkMap)|\(showContours)|\(preciseLocationsOnly)|\(showLinks)|\(accessoryManager.activeDeviceNum ?? 0)|\(accessoryManager.isInBackground)"
	}

	var body: some View {
		SpatialMapView(model: model, scene: scene, traffic: traffic, preset: preset, showLinks: showLinks) { nodeNum in
			if let url = URL(string: "meshtastic:///nodes?nodenum=\(nodeNum)") {
				UIApplication.shared.open(url)
			}
		}
		// The window takes its size limits from these, so the user can resize the table between them.
		.frame(
			minWidth: points(SpatialVolumeFit.minimumSize.x), maxWidth: points(SpatialVolumeFit.maximumSize.x),
			minHeight: points(SpatialVolumeFit.minimumSize.y), maxHeight: points(SpatialVolumeFit.maximumSize.y)
		)
		.frame(minDepth: points(SpatialVolumeFit.minimumSize.z), maxDepth: points(SpatialVolumeFit.maximumSize.z))
		.volumeBaseplateVisibility(.visible)
		.ornament(attachmentAnchor: .scene(.bottomFront)) {
			SpatialMapOrnament(
				model: model, traffic: traffic, mapLayer: $mapLayer, darkMap: $darkMap, showContours: $showContours,
				showLabels: $showLabels, showLinks: $showLinks, showTraffic: $showTraffic, autoTerrain: $autoTerrain
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

	private func points(_ meters: Double) -> CGFloat {
		metrics.convert(CGFloat(meters), from: .meters)
	}

	private func refresh() {
		model.connectedNodeNum = accessoryManager.activeDeviceNum
		traffic.connectedNodeNum = accessoryManager.activeDeviceNum
		traffic.preset = preset
		model.showLinks = showLinks
		model.showContours = showContours
		model.autoDownloadTerrain = autoTerrain
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
	@Binding var showContours: Bool
	@Binding var showLabels: Bool
	@Binding var showLinks: Bool
	@Binding var showTraffic: Bool
	@Binding var autoTerrain: Bool
	@ObservedObject private var offline = OfflineMapManager.shared
	@State private var confirmingTerrainDownload = false

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
				Toggle(isOn: $showContours) {
					Label(String(localized: "Contour Lines"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
				}
				Toggle(isOn: $autoTerrain) {
					Label(String(localized: "Download Terrain Automatically", comment: "Spatial map menu: keep the volume's area covered by elevation data without asking"), systemImage: "arrow.down.circle.dotted")
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

			terrainDownload

			if model.zoom > 1.01 {
				Button {
					model.resetZoom()
				} label: {
					Label {
						Text(verbatim: "\(model.zoom.formatted(.number.precision(.fractionLength(0...1))))×")
					} icon: {
						Image(systemName: "plus.magnifyingglass")
					}
					.labelStyle(.titleAndIcon)
					.fixedSize()
				}
				.help(String(localized: "Reset zoom", comment: "Spatial map: button showing how far the map is zoomed in; tapping it zooms back out to the whole mesh"))
				.accessibilityLabel(String(localized: "Reset zoom", comment: "Spatial map: button showing how far the map is zoomed in; tapping it zooms back out to the whole mesh"))
				.accessibilityValue(Text(verbatim: "\(model.zoom.formatted(.number.precision(.fractionLength(0...1))))×"))
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
		.alert(
			String(localized: "Terrain Download Failed", comment: "Spatial map: alert title when downloading terrain for the volume fails"),
			isPresented: Binding(get: { model.terrainDownloadError != nil }, set: { if !$0 { model.terrainDownloadError = nil } })
		) {
			Button("OK") {}
		} message: {
			Text(model.terrainDownloadError ?? "")
		}
	}

	/// Progress while terrain downloads. Otherwise, when the terrain doesn't cover the box: the
	/// Download Terrain button if automatic downloads are off or have given up on this area, a
	/// retry after an automatic download failed, or why terrain can't be downloaded.
	@ViewBuilder private var terrainDownload: some View {
		if model.isDownloadingTerrain {
			HStack(spacing: 6) {
				if let fraction = offline.activeDownload?.fractionCompleted {
					ProgressView(value: fraction)
						.frame(width: 80)
				} else {
					ProgressView().controlSize(.small)
				}
				Button {
					model.cancelTerrainDownload()
				} label: {
					Image(systemName: "xmark.circle")
				}
				.accessibilityLabel(String(localized: "Cancel terrain download", comment: "VoiceOver label to stop the spatial map terrain download"))
			}
			.accessibilityElement(children: .contain)
			.accessibilityLabel(String(localized: "Downloading terrain", comment: "VoiceOver label for the spatial map terrain download progress"))
		} else if let decision = model.terrainDecision(manager: offline) {
			if let target = decision.target {
				if let note = model.terrainDownloadNote {
					caption(note)
					Button {
						model.startTerrainDownload()
					} label: {
						Image(systemName: "arrow.clockwise")
					}
					.accessibilityLabel(String(localized: "Retry terrain download", comment: "VoiceOver label to retry the spatial map terrain download after it failed"))
				} else if !autoTerrain || model.autoDownloadGaveUp(on: target) {
					Button {
						confirmingTerrainDownload = true
					} label: {
						Label(String(localized: "Download Terrain", comment: "Spatial map: button that downloads elevation data so the volume shows relief"), systemImage: "arrow.down.circle")
							.labelStyle(.titleAndIcon)
					}
					.accessibilityHint(String(localized: "Downloads elevation data so the map shows hills and valleys.", comment: "VoiceOver hint for the spatial map terrain download button"))
					.confirmationDialog(
						String(localized: "Download terrain for this area?", comment: "Spatial map: title of the terrain download confirmation"),
						isPresented: $confirmingTerrainDownload,
						titleVisibility: .visible
					) {
						Button("Download") { model.startTerrainDownload() }
						Button("Cancel", role: .cancel) {}
					} message: {
						Text(terrainDownloadMessage(target))
					}
				}
			} else if case .blocked(let block) = decision {
				switch block {
				case .storage:
					caption(String(localized: "Offline map storage is full. Delete a map in Offline Maps to download terrain for the whole mesh.", comment: "Spatial map: terrain for the whole mesh does not fit in the offline map storage limit"))
				case .tooLarge:
					caption(String(localized: "The mesh is too spread out to download terrain for all of it.", comment: "Spatial map: the area around the mesh is over the per-map download limit"))
				}
			}
		}
	}

	private func caption(_ text: String) -> some View {
		Text(text)
			.font(.caption)
			.foregroundStyle(.secondary)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: 260)
	}

	private func terrainDownloadMessage(_ target: GeoBounds) -> String {
		let area = target.sizeInMeters
		let style = Measurement<UnitLength>.FormatStyle(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0)))
		let size = "\(Measurement(value: area.width, unit: UnitLength.meters).formatted(style)) × \(Measurement(value: area.height, unit: UnitLength.meters).formatted(style))"
		let bytes = ByteCountFormatter.string(fromByteCount: SpatialTerrainAutoDecision.estimatedBytes(target), countStyle: .file)
		return String(localized: "Downloads about \(bytes) of elevation data for a \(size) area around the mesh.", comment: "Spatial map: terrain download confirmation; the arguments are the download size, e.g. 40 MB, and the area's width × height, e.g. 98 km × 104 km")
	}
}
#endif
