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
	@Environment(\.openWindow) private var openWindow
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.physicalMetrics) private var metrics
	@StateObject private var nodeFilters = NodeFilterParameters()
	@State private var model = SpatialMapModel()
	@ObservedObject private var connectivity = OfflineMapConnectivityMonitor.shared
	@State private var scene: SpatialSceneController
	@State private var traffic: SpatialTrafficController
	@AppStorage("mapLayer") private var mapLayer: MapLayer = .standard
	@AppStorage("enableMapPreciseLocationsOnly") private var preciseLocationsOnly = false
	@AppStorage("spatialMapDark") private var darkMap = true
	/// Shared with the 2D map's Contour Lines setting.
	@AppStorage("meshMapShowContours") private var showContours = false
	@AppStorage("spatialMapShowLabels") private var showLabels = true
	@AppStorage("spatialMapShowTraffic") private var showTraffic = true
	@AppStorage("spatialMapShowDirectLinks") private var showLinks = false
	@AppStorage("spatialMapAutoTerrain") private var autoTerrain = true
	@AppStorage("spatialMapCoverage") private var coverageMode: SpatialCoverageMode = .selected
	@AppStorage("spatialMapCoverageOpacity") private var coverageOpacity = 0.55

	init() {
		let scene = SpatialSceneController()
		_scene = State(initialValue: scene)
		_traffic = State(initialValue: SpatialTrafficController(scene: scene))
	}

	private var preset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	private var refreshKey: String {
		"\(mapLayer.rawValue)|\(darkMap)|\(showContours)|\(preciseLocationsOnly)|\(showLinks)|\(coverageMode.rawValue)|\(accessoryManager.activeDeviceNum ?? 0)|\(accessoryManager.isInBackground)"
	}

	var body: some View {
		SpatialMapView(model: model, scene: scene, traffic: traffic, preset: preset) { nodeNum in
			showInMainWindow("meshtastic:///nodes?nodenum=\(nodeNum)")
		} onCoverage: { nodeNum, action in
			handleCoverage(action, nodeNum: nodeNum)
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
				showLabels: $showLabels, showLinks: $showLinks, showTraffic: $showTraffic, autoTerrain: $autoTerrain,
				coverageMode: $coverageMode, coverageOpacity: $coverageOpacity
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
		.onChange(of: coverageOpacity, initial: true) { _, opacity in
			model.coverageOpacity = Float(opacity)
		}
		.onChange(of: connectivity.isNetworkAvailable) { wasAvailable, isAvailable in
			if !wasAvailable && isAvailable { model.retryImagery() }
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
			SpatialTerrainKeeper.shared.volumeAppeared()
			claimFocus()
			if !Self.mainWindowIsOpen {
				dismissWindow(id: SpatialMapScene.id)
			}
		}
		.onDisappear {
			SpatialTerrainKeeper.shared.volumeDisappeared()
		}
		.onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { _ in
			if !Self.mainWindowIsOpen {
				dismissWindow(id: SpatialMapScene.id)
			}
		}
		.trackScreen(.spatialMap)
		#if DEBUG
		.task { await showRouteForScreenshots() }
		#endif
	}

	#if DEBUG
	/// Simulator screenshots: `--meshtastic-spatial-route [index]` flies the newest trace route
	/// with positions (or the one at `index`) at high speed and leaves it drawn.
	/// `--meshtastic-spatial-route-zoom` zooms in on its first relay first, and
	/// `--meshtastic-spatial-tilt <degrees>` tips the table toward the camera.
	private func showRouteForScreenshots() async {
		let arguments = ProcessInfo.processInfo.arguments
		tiltForScreenshots(arguments)
		guard let flagIndex = arguments.firstIndex(of: "--meshtastic-spatial-route") else { return }
		let index = arguments.indices.contains(flagIndex + 1) ? Int(arguments[flagIndex + 1]) ?? 0 : 0
		var waited = 0
		while model.routes.count <= index || model.placement == nil, waited < 60 {
			guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
			waited += 1
		}
		guard model.routes.indices.contains(index) else { return }
		let route = model.routes[index]
		Logger.services.info("🧪 [Spatial] Showing route \(route.id, privacy: .public) (launch argument)")
		if arguments.contains("--meshtastic-spatial-route-zoom"), let relay = route.layout.badges.first?.num ?? route.layout.targetNum {
			model.zoomIn(on: relay)
			guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
		}
		model.shownRoute = route
		traffic.startFlyover(route, speed: 10)
	}

	/// The simulator's camera looks at the table edge on; tip it toward the viewer.
	private func tiltForScreenshots(_ arguments: [String]) {
		if let tiltIndex = arguments.firstIndex(of: "--meshtastic-spatial-tilt"), arguments.indices.contains(tiltIndex + 1),
		   let degrees = Float(arguments[tiltIndex + 1]) {
			scene.root.orientation = simd_quatf(angle: degrees * .pi / 180, axis: [1, 0, 0])
			// Smaller and lifted so the near edge, now lower, stays inside the volume.
			scene.root.scale = SIMD3(repeating: 0.75)
			scene.model.position.y += 0.45 * sin(degrees * .pi / 180)
		}
	}
	#endif

	private func points(_ meters: Double) -> CGFloat {
		metrics.convert(CGFloat(meters), from: .meters)
	}

	private func refresh() {
		model.connectedNodeNum = accessoryManager.activeDeviceNum
		traffic.connectedNodeNum = accessoryManager.activeDeviceNum
		traffic.preset = preset
		model.showContours = showContours
		model.showLinks = showLinks
		model.autoDownloadTerrain = autoTerrain
		model.coverageMode = coverageMode
		model.refresh(context: context, filters: nodeFilters, preciseOnly: preciseLocationsOnly, layer: mapLayer, dark: darkMap)
		// The distance filter measures from the connected radio.
		if let num = accessoryManager.activeDeviceNum, let coordinate = model.nodesByNum[num]?.coordinate {
			let current = nodeFilters.fallbackLocation
			if current == nil || abs(current!.latitude - coordinate.latitude) > 1e-7 || abs(current!.longitude - coordinate.longitude) > 1e-7 {
				nodeFilters.fallbackLocation = coordinate
			}
		}
	}

	/// The estimate runs in the main window's form, which has the antenna settings and a full-size
	/// window for the planner. Show and hide flip the file's visibility, shared with the 2D map.
	private func handleCoverage(_ action: SpatialCoverageAction, nodeNum: Int64) {
		switch action {
		case .estimate:
			showInMainWindow("meshtastic:///map?coverage=1&nodenum=\(nodeNum)")
		case .show, .hide:
			guard let file = model.coverageByNode[nodeNum] else { return }
			GeoJSONOverlayManager.shared.setFileActive(file.fileID, action == .show)
			if action == .show, coverageMode == .off {
				coverageMode = .selected
				model.coverageMode = .selected
			}
			model.coverageFilesChanged()
		}
	}

	/// Opens the showcase and, once it is showing, closes this volume: the showcase is one space,
	/// and the map moves onto its desk.
	private func claimFocus() {
		guard let nodeNum = appState.claimSpatialMapFocus() else { return }
		model.focus(on: nodeNum)
		refresh()
	}

	/// Hands a route to the main window, which comes forward to show it. Opening the URL with
	/// UIApplication doesn't reach the main window from the volume.
	private func showInMainWindow(_ route: String) {
		guard let url = URL(string: route) else { return }
		appState.pendingRoute = PendingRoute(url: url, bringForward: true)
		// With no main window, open one; it takes the route as it appears.
		if appState.mainWindowCount == 0 {
			openWindow(id: MeshtasticAppleApp.mainWindowID)
		}
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

/// The volume's bottom toolbar: map layer, what to show, trace routes, and the node count.
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
	@Binding var coverageMode: SpatialCoverageMode
	@Binding var coverageOpacity: Double
	@ObservedObject private var offline = OfflineMapManager.shared
	@State private var confirmingTerrainDownload = false

	var body: some View {
		HStack(spacing: 10) {
			Menu {
				// Offline is offered only where a downloaded basemap covers the map. The setting is
				// shared with the 2D map, so a stored Offline shows as Standard elsewhere.
				let offlineAvailable = model.offlineLayerAvailable(regions: offline.regions)
				Picker(String(localized: "Map Layer", comment: "Spatial map: picker for the image draped over the terrain"), selection: Binding(
					get: { SpatialOfflineMap.buildLayer(mapLayer, offlineAvailable: offlineAvailable) },
					set: { mapLayer = $0 }
				)) {
					ForEach(SpatialOfflineMap.layers(offlineAvailable: offlineAvailable), id: \.self) { layer in
						Text(layer.localized).tag(layer)
					}
				}
				Toggle(isOn: $darkMap) {
					Label(String(localized: "Dark Map", comment: "Spatial map: draw the map in its dark appearance"), systemImage: "moon")
				}
				Toggle(isOn: $showContours) {
					Label(String(localized: "Contour Lines"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
				}
				coverageMenu
				Toggle(isOn: $autoTerrain) {
					Label(String(localized: "Download Terrain Automatically", comment: "Spatial map menu: keep the volume's area covered by elevation data without asking"), systemImage: "arrow.down.circle.dotted")
				}
			} label: {
				Image(systemName: "map")
			}
			.help(String(localized: "Map layer", comment: "VoiceOver label for the spatial map layer menu"))
			.accessibilityLabel(String(localized: "Map layer", comment: "VoiceOver label for the spatial map layer menu"))

			Toggle(isOn: $showLabels) { Image(systemName: "tag") }
				.help(String(localized: "Node labels", comment: "VoiceOver label for the spatial map labels toggle"))
				.accessibilityLabel(String(localized: "Node labels", comment: "VoiceOver label for the spatial map labels toggle"))
			Toggle(isOn: $showLinks) { Image(systemName: "link") }
				.help(String(localized: "Direct Links", comment: "Map settings toggle that draws lines between nodes that hear each other directly."))
				.accessibilityLabel(String(localized: "Direct Links", comment: "Map settings toggle that draws lines between nodes that hear each other directly."))
			Toggle(isOn: $showTraffic) { Image(systemName: "dot.radiowaves.left.and.right") }
				.help(String(localized: "Live traffic", comment: "VoiceOver label for the spatial map traffic toggle"))
				.accessibilityLabel(String(localized: "Live traffic", comment: "VoiceOver label for the spatial map traffic toggle"))

			traceRoutes

			terrainDownload

			Button {
				model.setZoom(model.clampedZoom(model.zoom / 2))
			} label: {
				Image(systemName: "minus.magnifyingglass")
			}
			.disabled(model.zoom <= 1.01)
			.help(String(localized: "Zoom out", comment: "Spatial map: show a wider area on the table"))
			.accessibilityLabel(String(localized: "Zoom out", comment: "Spatial map: show a wider area on the table"))
			Button {
				model.setZoom(model.clampedZoom(model.zoom * 2))
			} label: {
				Image(systemName: "plus.magnifyingglass")
			}
			.disabled(model.clampedZoom(model.zoom * 2) <= model.zoom + 0.01)
			.help(String(localized: "Zoom in", comment: "Spatial map: show a smaller area on the table in more detail"))
			.accessibilityLabel(String(localized: "Zoom in", comment: "Spatial map: show a smaller area on the table in more detail"))
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
				if model.shownRoute != nil {
					SpatialRouteLegend()
				}
				if !model.coverageLegend.isEmpty {
					SpatialCoverageLegendStrip(entries: model.coverageLegend)
				}
				if model.imageryUnavailable {
					Image(systemName: "wifi.slash")
						.foregroundStyle(.secondary)
						.help(model.textureSource == .offlineMap
							? String(localized: "Map imagery unavailable; showing the offline map", comment: "Spatial map: the Apple map image could not be fetched, so the downloaded offline map is shown")
							: String(localized: "Map imagery unavailable; showing terrain shading", comment: "Spatial map: the Apple map image could not be fetched"))
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

	/// The trace route menu: pick a route to fly it and leave it drawn. Picking another replaces it.
	/// While one is shown, a clear button sits beside the menu.
	@ViewBuilder private var traceRoutes: some View {
		Menu {
			if model.routes.isEmpty {
				Text("No traceroutes with positions", comment: "Spatial map: trace route menu is empty")
			}
			let now = Date.now
			ForEach(model.routes) { route in
				let entry = SpatialRouteMenuEntry(route: route, now: now)
				Button {
					model.shownRoute = route
					traffic.startFlyover(route)
				} label: {
					Text(verbatim: entry.title)
					Text(verbatim: entry.subtitle)
				}
			}
		} label: {
			Image(systemName: "point.3.connected.trianglepath.dotted")
		}
		.help(String(localized: "Trace routes", comment: "VoiceOver label for the spatial map trace route menu"))
		.accessibilityLabel(String(localized: "Trace routes", comment: "VoiceOver label for the spatial map trace route menu"))
		.accessibilityHint(String(localized: "Pick a trace route to fly along it and leave it drawn on the map.", comment: "VoiceOver hint for the spatial map trace route menu"))
		if model.shownRoute != nil {
			Button {
				traffic.stopFlyover()
				model.shownRoute = nil
			} label: {
				Image(systemName: "xmark")
			}
			.help(String(localized: "Clear trace route", comment: "VoiceOver label for the clear trace route button"))
			.accessibilityLabel(String(localized: "Clear trace route", comment: "VoiceOver label for the clear trace route button"))
		}
	}

	/// Progress while the offline map downloads. Otherwise, when streets and terrain don't cover the
	/// box: the Download Terrain button if automatic downloads are off or have given up on this
	/// area, a retry after an automatic download failed, or why it can't be downloaded.
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
				.help(String(localized: "Cancel terrain download", comment: "VoiceOver label to stop the spatial map terrain download"))
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
					.help(String(localized: "Retry terrain download", comment: "VoiceOver label to retry the spatial map terrain download after it failed"))
					.accessibilityLabel(String(localized: "Retry terrain download", comment: "VoiceOver label to retry the spatial map terrain download after it failed"))
				} else if !autoTerrain || model.autoDownloadGaveUp(on: target) {
					Button {
						confirmingTerrainDownload = true
					} label: {
						Label(String(localized: "Download Terrain", comment: "Spatial map: button that downloads elevation data so the volume shows relief"), systemImage: "arrow.down.circle")
							.labelStyle(.titleAndIcon)
					}
					.help(String(localized: "Downloads elevation data so the map shows hills and valleys.", comment: "VoiceOver hint for the spatial map terrain download button"))
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
			} else if model.streetsLeftOut {
				caption(String(localized: "The street map for the mesh is over the per-map limit, so only terrain was downloaded.", comment: "Spatial map: the offline map kept for the mesh has terrain but no streets because the street map is too large"))
			}
		}
	}

	/// Which estimates to drape and how strongly. A picker rather than a slider, since sliders work
	/// poorly inside a menu.
	@ViewBuilder private var coverageMenu: some View {
		Picker(selection: $coverageMode) {
			Text(String(localized: "Off")).tag(SpatialCoverageMode.off)
			Text(String(localized: "Selected Node", comment: "Spatial map coverage option: show the selected node's coverage estimate")).tag(SpatialCoverageMode.selected)
			Text(String(localized: "All Estimates", comment: "Spatial map coverage option: show every coverage estimate in the area")).tag(SpatialCoverageMode.all)
		} label: {
			Label(String(localized: "Coverage", comment: "Spatial map menu: which Site Planner coverage estimates to show on the terrain"), systemImage: "antenna.radiowaves.left.and.right")
		}
		.pickerStyle(.menu)
		Picker(selection: $coverageOpacity) {
			Text(String(localized: "Light", comment: "Spatial map coverage opacity option: most see-through")).tag(0.35)
			Text(String(localized: "Medium", comment: "Spatial map coverage opacity option")).tag(0.55)
			Text(String(localized: "Strong", comment: "Spatial map coverage opacity option: least see-through")).tag(0.8)
		} label: {
			Label(String(localized: "Coverage Opacity", comment: "Spatial map menu: how see-through the coverage overlay is"), systemImage: "circle.lefthalf.filled")
		}
		.pickerStyle(.menu)
		.disabled(coverageMode == .off)
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
		return String(localized: "Downloads about \(bytes) of street map and elevation data for a \(size) area around the mesh.", comment: "Spatial map: offline map download confirmation; the arguments are the download size, e.g. 40 MB, and the area's width × height, e.g. 98 km × 104 km")
	}
}

/// The route colors in the ornament while a route is shown: solid orange out, dashed blue back.
struct SpatialRouteLegend: View {
	var body: some View {
		HStack(spacing: 4) {
			Divider().frame(height: 14)
			line(dashed: false, color: TraceRouteColors.forward)
			Text("Forward route", comment: "Trace route timeline: heading for the path towards the target")
			line(dashed: true, color: TraceRouteColors.back)
			Text("Return route", comment: "Trace route timeline: heading for the path back from the target")
		}
		.accessibilityElement(children: .combine)
	}

	private func line(dashed: Bool, color: Color) -> some View {
		Path { path in
			path.move(to: CGPoint(x: 1, y: 3))
			path.addLine(to: CGPoint(x: 17, y: 3))
		}
		.stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dashed ? [3, 3] : []))
		.frame(width: 18, height: 6)
		.environment(\.colorScheme, .dark)
	}
}

/// The coverage colors in the ornament: a swatch per signal level, strongest first, the range of
/// levels, and the dark "no signal" shade. The full labels are in the tooltip.
struct SpatialCoverageLegendStrip: View {
	let entries: [SpatialCoverageLegendEntry]
	static let maximumSwatches = 6

	var body: some View {
		let shown = Array(entries.prefix(Self.maximumSwatches))
		HStack(spacing: 4) {
			Divider().frame(height: 14)
			HStack(spacing: 1) {
				ForEach(shown) { entry in
					swatch(Color(.sRGB, red: entry.rgba.x, green: entry.rgba.y, blue: entry.rgba.z))
				}
			}
			if let strongest = shown.first, let weakest = shown.last {
				Text(verbatim: strongest.dbm == weakest.dbm
					 ? "\(Self.level(strongest.dbm)) dBm"
					 : "\(Self.level(strongest.dbm))…\(Self.level(weakest.dbm)) dBm")
					.monospacedDigit()
			}
			swatch(Color.black.opacity(SpatialCoverageTexture.shadow.w))
			Text("No signal", comment: "Spatial map legend: the dark shade where a coverage estimate found no signal")
				.foregroundStyle(.secondary)
		}
		.help(entries.map(\.label).joined(separator: "\n"))
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(String(localized: "Coverage legend", comment: "VoiceOver label for the spatial map coverage colors"))
		.accessibilityValue(entries.map(\.label).joined(separator: ", "))
	}

	private func swatch(_ color: Color) -> some View {
		RoundedRectangle(cornerRadius: 2)
			.fill(color)
			.frame(width: 10, height: 10)
	}

	private static func level(_ dbm: Double) -> String {
		dbm.formatted(.number.precision(.fractionLength(0)))
	}
}
#endif
