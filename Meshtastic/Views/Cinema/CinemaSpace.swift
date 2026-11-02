//
//  CinemaSpace.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
#if os(visionOS)
import CoreLocation
import RealityKit
import SwiftData
import SwiftUI

/// Root of the cinema immersive space: an environment around the viewer and a small panel to
/// change the environment, open the 3D map or leave. The front wall is a screen that shows
/// the app's sections, picked from a tab strip above it. The tent's whiteboard shows the live
/// team roster, the print by the door the latest trace route, and the second whiteboard the
/// nodes' status messages. "View in your space" on a 3D
/// model stands it in front of the seat. The main window closes while
/// the space is open and the 3D map opens in front of the viewer instead.
struct CinemaSpace: View {
	/// The store, for the boards. Nil when the app runs without one (demo mode).
	let container: ModelContainer?
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@EnvironmentObject private var lockdown: LockdownCoordinator
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
	@Environment(\.openWindow) private var openWindow
	@Environment(\.dismissWindow) private var dismissWindow
	@AppStorage("cinemaEnvironment") private var environment: CinemaEnvironment = .sarTent
	@State private var world = Entity()
	@State private var backdrop: Entity?
	@State private var panelGrabber = Self.makePanelGrabber()
	/// The point the image was rendered from, fixed at the seated eye height and turned so the
	/// image's center is in front. The backdrop and the boards hang from it, so one turn moves both.
	@State private var stage = Entity()
	@State private var fitBoards: EventSubscription?
	@State private var anchors: CinemaAnchors?
	@State private var boards = BoardPanels()
	/// A device model on a stand in front of the seat, from "View in your space" on a 3D model.
	@State private var modelStand = CinemaModelStand()
	@State private var modelRequest: CinemaModelRequest?
	/// Whether the radio the model on the stand is of reports a display, read with the model.
	@State private var modelHasDisplay = false
	/// The front screen's section and navigation, kept here so they outlive its attachment.
	@StateObject private var screen = CinemaScreenModel()
	/// The fire lookout's summits, and the terrain and node labels for the chosen one.
	@State private var lookout = LookoutScene()
	@AppStorage("cinemaLookoutSite") private var lookoutSiteID = ""
	/// Eighth turns clockwise the lookout is turned from the panel.
	@AppStorage(SpatialLookout.turnsKey) private var lookoutTurns = 0
	@State private var terrain: ModelEntity?
	/// The site the terrain and labels are built for; nil for the painted sunset.
	@State private var terrainSiteID: String?
	/// The bearing the cab faced when the terrain was built; the labels are placed from it too.
	@State private var terrainHeading = SpatialLookout.frontHeading
	/// The terrain being built, and the site and facing it's for. The cinema opening refreshes the
	/// lookout from two tasks at once; the second waits on the first one's build instead of
	/// starting another. The build is its own task so a caller being cancelled doesn't stop it.
	@State private var lookoutBuild: LookoutBuild?
	@State private var markerPanels = LookoutMarkerPanels()
	/// The node card open beside a marker out the lookout's windows.
	@State private var lookoutCard: LookoutCardSelection?
	@State private var radioCoordinate: CLLocationCoordinate2D?

	var body: some View {
		RealityView { content, attachments in
			world.name = "Cinema"
			content.add(world)
			stage.name = "CinemaStage"
			world.addChild(stage)
			world.addChild(modelStand.root)
			if let panel = attachments.entity(for: Attachments.panel) {
				panelGrabber.addChild(panel)
				seat(panel)
				panelGrabber.position = [0.45, 0.85, -0.7]
				world.addChild(panelGrabber)
			}
			// A panel's size is only known once SwiftUI has laid it out, so boards are fitted on
			// the first frame that has it.
			fitBoards = content.subscribe(to: SceneEvents.Update.self) { _ in
				placeBoards()
				modelStand.refreshScreen()
				// A marker's size is only known once it has laid out, like a board's.
				if markerPanels.unsized {
					placeMarkers { markerPanels.entity(for: $0) }
				}
			}
		} update: { _, attachments in
			if let panel = attachments.entity(for: Attachments.panel) {
				seat(panel)
			}
			for board in CinemaBoard.allCases {
				boards.set(attachments.entity(for: board.rawValue), for: board)
			}
			boards.setStrip(attachments.entity(for: Attachments.tabStrip))
			modelStand.setTag(attachments.entity(for: Attachments.modelTag))
			placeBoards()
			placeMarkers { attachments.entity(for: $0) }
		} attachments: {
			Attachment(id: Attachments.panel) {
				// The map counts as open while the cinema is reopening it, so the button doesn't
				// show for the second in between.
				CinemaPanel(environment: $environment, sites: lookout.sites, siteID: $lookoutSiteID, turns: $lookoutTurns, radioCoordinate: radioCoordinate, lookoutNote: lookoutNote, spatialMapOpen: appState.spatialMapWindowCount > 0 || appState.spatialMapReopening) {
					openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
				} onLeave: {
					Task { await dismissImmersiveSpace() }
				}
			}
			ForEach(markers, id: \.lead.id) { spot in
				Attachment(id: LookoutMarkerPanels.id(for: spot)) {
					LookoutNodeMarker(labels: spot.labels) {
						lookoutCard = lookoutCard?.lead == spot.lead.id ? nil : LookoutCardSelection(lead: spot.lead.id)
					}
				}
			}
			if let container, !appState.isDatabaseResetting, let selection = lookoutCard, let spot = markers.first(where: { $0.lead.id == selection.lead }) {
				Attachment(id: LookoutMarkerPanels.cardID) {
					LookoutNodeCard(labels: spot.labels, chosen: Binding { lookoutCard?.chosen } set: { lookoutCard?.chosen = $0 }, onShowOnMap: showOnMap) { nodeNum in
						appState.cinemaScreenRequest = .node(nodeNum)
					} onClose: {
						lookoutCard = nil
					}
					.id(appState.databaseResetID)
					.modelContainer(container)
				}
			}
			if let container, !appState.isDatabaseResetting, anchors?.board(.teamStatus) != nil {
				Attachment(id: CinemaBoard.teamStatus.rawValue) {
					live(TeamStatusBoard(), container: container)
				}
			}
			if let container, !appState.isDatabaseResetting, anchors?.board(.traceRoute) != nil {
				Attachment(id: CinemaBoard.traceRoute.rawValue) {
					live(TraceRouteBoard(), container: container)
				}
			}
			if let container, !appState.isDatabaseResetting, anchors?.board(.nodeStatus) != nil {
				Attachment(id: CinemaBoard.nodeStatus.rawValue) {
					live(NodeStatusBoard(environment: environment), container: container)
				}
			}
			if let modelRequest {
				Attachment(id: Attachments.modelTag) {
					// Without the store, the card only names the device.
					if let container, !appState.isDatabaseResetting {
						CinemaModelTag(request: modelRequest, liveScreen: standLiveScreen, zoom: modelStand.zoom, onZoom: { modelStand.setZoom($0) }, onInput: { event in
							Task { await accessoryManager.sendDisplayInput(event) }
						}) {
							self.modelRequest = nil
						}
						.id(appState.databaseResetID)
						.modelContainer(container)
					} else {
						CinemaModelTag(request: CinemaModelRequest(modelName: modelRequest.modelName, deviceName: modelRequest.deviceName, nodeNum: nil)) {
							self.modelRequest = nil
						}
					}
				}
			}
			// Out during a database reset like the boards; the screen's model keeps its navigation.
			if let container, !appState.isDatabaseResetting, anchors?.board(.screen) != nil {
				Attachment(id: CinemaBoard.screen.rawValue) {
					CinemaScreen(container: container, model: screen)
						.environmentObject(appState)
						.environmentObject(accessoryManager)
						.environmentObject(lockdown)
				}
				Attachment(id: Attachments.tabStrip) {
					CinemaTabStrip(model: screen)
				}
			}
		}
		.task(id: environment) {
			anchors = CinemaAnchors.load(for: environment)
			stage.position = [0, anchors?.eyeHeight ?? CinemaAnchors.seatedEyeHeight, 0]
			stage.orientation = simd_quatf(angle: environment.frontRotation, axis: [0, 1, 0])
			boards.unfitAll()
			await replaceBackdrop(clearSky: false)
			await refreshLookout()
		}
		.task(id: lookoutSiteID) {
			await refreshLookout()
		}
		.task(id: lookoutTurns) {
			await refreshLookout()
		}
		.task(id: terrainSiteID) {
			// The labels follow the nodes' positions, which move slowly.
			guard let container, let site = terrainSiteID.flatMap({ lookout.site(for: $0) }) else {
				lookout.labels = []
				return
			}
			while !Task.isCancelled {
				if !appState.isDatabaseResetting {
					let context = ModelContext(container)
					let radioNum = accessoryManager.isConnected ? accessoryManager.activeDeviceNum : nil
					lookout.labels = await lookout.labels(for: site, context: context, radioNum: radioNum)
				}
				try? await Task.sleep(for: .seconds(60))
			}
		}
		.task(id: accessoryManager.isConnected ? accessoryManager.activeDeviceNum : nil) {
			// Where the radio is, for each summit's distance and direction in the picker.
			guard let container, let radioNum = accessoryManager.isConnected ? accessoryManager.activeDeviceNum : nil else {
				radioCoordinate = nil
				return
			}
			while !Task.isCancelled {
				if !appState.isDatabaseResetting {
					radioCoordinate = getNodeInfo(id: radioNum, context: ModelContext(container))?.latestPosition?.nodeCoordinate
				}
				try? await Task.sleep(for: .seconds(60))
			}
		}
		#if DEBUG
		.task {
			// Simulator screenshots: `--meshtastic-cinema-model <model>` stands that model, as the
			// connected radio's once one connects, within a few seconds, else as a plain device.
			let arguments = CommandLine.arguments
			guard let index = arguments.firstIndex(of: "--meshtastic-cinema-model"), index + 1 < arguments.count else { return }
			for _ in 0..<40 where !accessoryManager.isConnected {
				try? await Task.sleep(for: .milliseconds(500))
			}
			let name = arguments[index + 1]
			modelRequest = CinemaModelRequest(modelName: name, deviceName: name, nodeNum: accessoryManager.isConnected ? accessoryManager.activeDeviceNum : nil)
		}
		#endif
		.task(id: modelRequest) {
			modelHasDisplay = false
			if let container, !appState.isDatabaseResetting, let nodeNum = modelRequest?.nodeNum {
				modelHasDisplay = getNodeInfo(id: nodeNum, context: ModelContext(container))?.metadata?.hasDisplay == true
			}
			await modelStand.show(modelRequest, environment: environment)
		}
		// The stream is only wanted while the connected radio's model is on the stand. Asked for
		// again after a reconnect, which forgets it.
		.task(id: standLiveScreen) {
			modelStand.screenSource = standLiveScreen ? accessoryManager.displayMirror : nil
			if standLiveScreen {
				accessoryManager.startDisplayMirror(for: .cinemaStand)
			} else {
				accessoryManager.stopDisplayMirror(for: .cinemaStand)
			}
		}
		.onChange(of: lookout.labels) {
			// The nodes move and the markers regroup; a card whose marker is gone closes.
			if let lead = lookoutCard?.lead, !markers.contains(where: { $0.lead.id == lead }) {
				lookoutCard = nil
			}
		}
		.onAppear {
			appState.cinemaOpen = true
			CinemaScene.showModel = { request in modelRequest = request }
			appState.spatialMapReopening = true
			screen.register(with: appState.sceneRouters)
		}
		.onChange(of: appState.cinemaScreenRequest) {
			if let request = appState.claimCinemaScreenRequest() {
				screen.show(request)
			}
		}
		.task {
			// The screen takes the main window's place. Once the space has settled, close the window
			// and reopen the map: with no window to sit beside, the system puts it in front of the
			// viewer, between them and the screen. Until the map is back, a board's focus or route
			// request waits for it (`spatialMapReopening`); the map about to close would take it.
			defer { appState.spatialMapReopening = false }
			try? await Task.sleep(for: .seconds(2))
			guard appState.cinemaOpen else { return }
			if appState.mainWindowCount > 0 {
				dismissWindow(id: MeshtasticAppleApp.mainWindowID)
				CinemaScene.closedMainWindow = true
			}
			dismissWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
			try? await Task.sleep(for: .seconds(1))
			guard appState.cinemaOpen else { return }
			openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
		}
		.onDisappear {
			fitBoards?.cancel()
			fitBoards = nil
			CinemaScene.showModel = nil
			modelRequest = nil
			modelStand.screenSource = nil
			accessoryManager.stopDisplayMirror(for: .cinemaStand)
			appState.cinemaOpen = false
			screen.unregister(from: appState.sceneRouters)
			// Bring the main window back. Not when the app went to the background, which closes the
			// cinema too; but the space also reports .background while it closes, so when the
			// cinema closed the window itself, always. The fallback for the reopen below.
			if scenePhase != .background || CinemaScene.closedMainWindow {
				CinemaScene.reopenMainWindow(openWindow, appState: appState)
			}
			CinemaScene.closedMainWindow = false
		}
		.onChange(of: scenePhase) { _, phase in
			switch phase {
			case .inactive:
				// On the way to the background (Digital Crown, headset off) the system takes the
				// space down, and a backgrounded app may not get to open a window. So when the
				// cinema closed the window, it comes back now, while the app is still in the
				// foreground. If this was only a pause, the window sits in the tent.
				if CinemaScene.closedMainWindow {
					CinemaScene.reopenMainWindow(openWindow, appState: appState)
				}
			case .background:
				Task { await dismissImmersiveSpace() }
			default:
				break
			}
		}
		.trackScreen(.cinema)
	}

	/// The board panels SwiftUI has made, and which of them are placed.
	private final class BoardPanels {
		var panels: [CinemaBoard: Entity] = [:]
		var fitted: Set<CinemaBoard> = []
		/// The tab strip above the screen, placed with the screen.
		var strip: Entity?
		var stripFitted = false

		/// Keeps the board's panel, taking the old one out of the scene when SwiftUI drops or
		/// replaces it (a database reset).
		func set(_ panel: Entity?, for board: CinemaBoard) {
			guard panels[board] !== panel else { return }
			panels[board]?.removeFromParent()
			panels[board] = panel
			fitted.remove(board)
			if board == .screen { stripFitted = false }
		}

		func setStrip(_ panel: Entity?) {
			guard strip !== panel else { return }
			strip?.removeFromParent()
			strip = panel
			stripFitted = false
		}

		var allFitted: Bool {
			fitted.count == panels.count && (strip == nil || stripFitted)
		}

		func unfitAll() {
			fitted.removeAll()
			stripFitted = false
		}
	}

	private struct LookoutBuild {
		let siteID: String
		let heading: Double
		let task: Task<ModelEntity?, Never>
	}

	private enum Attachments {
		static let panel = "panel"
		static let tabStrip = "screenTabs"
		static let modelTag = "modelTag"
	}

	/// What the panel says in the lookout while there is no summit to pick.
	private var lookoutNote: String? {
		switch lookout.status {
		case .searching:
			String(localized: "Looking for summits in the downloaded terrain…", comment: "Cinema lookout: shown on the panel while the summits are being found")
		case .noTerrain:
			String(localized: "Download terrain for the 3D map to stand the lookout on a real summit.", comment: "Cinema lookout: shown on the panel when no terrain has been downloaded")
		case .noSummits:
			String(localized: "No summits found in the downloaded terrain.", comment: "Cinema lookout: shown on the panel when the downloaded terrain gave no summits")
		case .idle, .ready:
			nil
		}
	}

	/// The backdrop for the environment: its image, and for a cutout, the sky behind it.
	private func replaceBackdrop(clearSky: Bool) async {
		let next = await CinemaBackdrop.make(environment, clearSky: clearSky)
		backdrop?.removeFromParent()
		stage.addChild(next)
		backdrop = next
	}

	/// Puts the terrain for the chosen summit out the lookout's windows, with the clear sky behind
	/// it, or takes it away for the painted sunset or another environment.
	private func refreshLookout() async {
		guard environment.isCutout else {
			terrain?.removeFromParent()
			terrain = nil
			terrainSiteID = nil
			return
		}
		if lookout.sites.isEmpty {
			await lookout.prepare()
		}
		let site = lookout.site(for: lookoutSiteID)
		let heading = SpatialLookout.heading(turns: lookoutTurns)
		guard site?.id != terrainSiteID || heading != terrainHeading || (site != nil && terrain == nil) else { return }
		terrain?.removeFromParent()
		terrain = nil
		terrainSiteID = nil
		guard let site else {
			lookoutBuild?.task.cancel()
			lookoutBuild = nil
			await replaceBackdrop(clearSky: false)
			return
		}
		let build: Task<ModelEntity?, Never>
		if let current = lookoutBuild, current.siteID == site.id, current.heading == heading {
			build = current.task
		} else {
			lookoutBuild?.task.cancel()
			let sun = environment.sun
			build = Task { await lookout.terrain(for: site, heading: heading, sun: sun) }
			lookoutBuild = LookoutBuild(siteID: site.id, heading: heading, task: build)
		}
		let built = await build.value
		if lookoutBuild?.task == build {
			lookoutBuild = nil
		}
		// Kept only if the summit and the turn are still the ones chosen, and the other caller
		// waiting on the same build hasn't already put it up. Checked again after the backdrop
		// changes, since either can change while it does.
		func stillWanted() -> Bool {
			lookoutSiteID == site.id && SpatialLookout.heading(turns: lookoutTurns) == heading && environment.isCutout
				&& !(terrain != nil && terrainSiteID == site.id && terrainHeading == heading)
		}
		guard let entity = built, stillWanted() else { return }
		await replaceBackdrop(clearSky: true)
		guard stillWanted() else { return }
		terrain?.removeFromParent()
		stage.addChild(entity)
		terrain = entity
		terrainSiteID = site.id
		terrainHeading = heading
	}

	/// Show the connected radio's screen live on the model on the stand: the model is of the
	/// connected radio, the radio reports a display, and the model has one to draw it on. The
	/// screen only comes over the local connection, as in the Device Screen view.
	private var standLiveScreen: Bool {
		guard let nodeNum = modelRequest?.nodeNum, modelHasDisplay, modelStand.hasScreen else { return false }
		return nodeNum == accessoryManager.activeDeviceNum && accessoryManager.isConnected
	}

	/// The markers out the lookout's windows, nearest node first.
	private var markers: [LookoutTerrain.MarkerSpot] {
		LookoutTerrain.markers(for: lookout.labels, heading: terrainHeading)
	}

	private func placeMarkers(_ entityFor: (String) -> Entity?) {
		markerPanels.place(markers, selected: lookoutCard?.lead, on: stage, entityFor: entityFor)
	}

	/// Centers the 3D map on the node, opening the map if it isn't open.
	private func showOnMap(_ nodeNum: Int64) {
		appState.spatialMapFocus = SpatialMapFocusRequest(nodeNum: nodeNum)
		openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
	}

	/// A board's view with the store and app state it reads, remade on a database reset.
	private func live(_ board: some View, container: ModelContainer) -> some View {
		board
			.id(appState.databaseResetID)
			.modelContainer(container)
			.environmentObject(appState)
			.environmentObject(accessoryManager)
	}

	/// Puts each board's panel over its board in the image, out by the backdrop so both eyes see it
	/// at the painting's depth, and scaled so it covers the same part of the view.
	private func placeBoards() {
		guard !boards.allFitted, let anchors else { return }
		for (board, panel) in boards.panels where !boards.fitted.contains(board) {
			guard let anchor = anchors.board(board) else { continue }
			if panel.parent !== stage {
				stage.addChild(panel)
			}
			// Measured without the screen's bezel, which goes around the panel.
			CinemaBezel.remove(from: panel)
			let size = panel.visualBounds(relativeTo: panel).extents
			guard size.x > 0, size.y > 0 else { continue }
			let push = anchor.distanceScale(within: CinemaBackdrop.radius * 0.96)
			panel.scale = SIMD3(repeating: push * min(anchor.width / size.x, anchor.height / size.y))
			panel.position = anchor.position * push
			panel.orientation = anchor.orientation
			if board == .screen {
				CinemaBezel.add(to: panel, pointWidth: CinemaScreen.size.width, cornerRadius: CinemaScreen.cornerRadius)
			}
			boards.fitted.insert(board)
		}
		placeTabStrip(anchors)
	}

	/// The tab strip sits just above the screen and a little in front of it, pushed out with it.
	/// Its points are a little smaller than the screen's.
	private func placeTabStrip(_ anchors: CinemaAnchors) {
		guard !boards.stripFitted, let strip = boards.strip, let screenPanel = boards.panels[.screen],
			  boards.fitted.contains(.screen), let anchor = anchors.board(.screen) else { return }
		if strip.parent !== stage {
			stage.addChild(strip)
		}
		let size = strip.visualBounds(relativeTo: strip).extents
		guard size.x > 0, size.y > 0 else { return }
		let push = anchor.distanceScale(within: CinemaBackdrop.radius * 0.96)
		let up = anchor.orientation.act([0, 1, 0])
		let front = anchor.orientation.act([0, 0, 1])
		strip.scale = screenPanel.scale * 0.75
		strip.position = (anchor.position + up * (anchor.height / 2 + 0.125) + front * 0.05) * push
		strip.orientation = anchor.orientation
		boards.stripFitted = true
	}

	/// The panel sits just above the grab bar, however tall it is.
	private func seat(_ panel: Entity) {
		let height = panel.visualBounds(relativeTo: panel).extents.y
		panel.position = [0, height / 2 + 0.012, 0]
	}

	/// A bar like a window's: pinch and drag it to move the panel. It and the panel keep facing
	/// the viewer.
	private static func makePanelGrabber() -> Entity {
		var material = UnlitMaterial(color: .white)
		material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
		let bar = ModelEntity(mesh: .generateBox(width: 0.08, height: 0.008, depth: 0.008, cornerRadius: 0.004), materials: [material])
		bar.name = "PanelGrabber"
		ManipulationComponent.configureEntity(
			bar,
			hoverEffect: .highlight(.default),
			allowedInputTypes: .all,
			collisionShapes: [.generateBox(width: 0.14, height: 0.035, depth: 0.03)]
		)
		var manipulation = bar.components[ManipulationComponent.self] ?? ManipulationComponent()
		manipulation.releaseBehavior = .stay
		manipulation.dynamics.scalingBehavior = .none
		manipulation.dynamics.primaryRotationBehavior = .none
		manipulation.dynamics.secondaryRotationBehavior = .none
		bar.components.set(manipulation)
		bar.components.set(BillboardComponent())
		var accessibility = AccessibilityComponent()
		accessibility.isAccessibilityElement = true
		accessibility.label = LocalizedStringResource("Move the cinema panel", comment: "Cinema: VoiceOver label for the bar under the panel that moves it")
		bar.components.set(accessibility)
		return bar
	}
}
#endif
