//
//  CinemaSpace.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
#if os(visionOS)
import RealityKit
import SwiftData
import SwiftUI

/// Root of the cinema immersive space: an environment around the viewer and a small panel to
/// change the environment, open the 3D map or leave. The front wall is a screen that shows
/// the app's sections, picked from a tab strip above it. The tent's whiteboard shows the live
/// team roster, and the print by the door the latest trace route. "View in your space" on a 3D
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
	/// The front screen's section and navigation, kept here so they outlive its attachment.
	@StateObject private var screen = CinemaScreenModel()

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
		} attachments: {
			Attachment(id: Attachments.panel) {
				// The map counts as open while the cinema is reopening it, so the button doesn't
				// show for the second in between.
				CinemaPanel(environment: $environment, spatialMapOpen: appState.spatialMapWindowCount > 0 || appState.spatialMapReopening) {
					openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
				} onLeave: {
					Task { await dismissImmersiveSpace() }
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
			if let modelRequest {
				Attachment(id: Attachments.modelTag) {
					// Without the store, the card only names the device.
					if let container, !appState.isDatabaseResetting {
						CinemaModelTag(request: modelRequest) { self.modelRequest = nil }
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
			let next = await CinemaBackdrop.make(environment)
			backdrop?.removeFromParent()
			stage.addChild(next)
			backdrop = next
		}
		.task(id: modelRequest) {
			await modelStand.show(modelRequest, environment: environment)
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

	private enum Attachments {
		static let panel = "panel"
		static let tabStrip = "screenTabs"
		static let modelTag = "modelTag"
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
