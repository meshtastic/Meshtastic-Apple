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

/// Root of the cinema immersive space: an environment around the viewer and the app's windows,
/// and a small panel to change the environment or leave. The app stays in its own window, which
/// can be moved back and made bigger like a screen; a window drawn inside the space can't show the
/// tab bar or sheets. The 3D map opens beside it. The tent's whiteboard shows the live team
/// roster.
struct CinemaSpace: View {
	/// The store, for the team board. Nil when the app runs without one (demo mode).
	let container: ModelContainer?
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
	@Environment(\.openWindow) private var openWindow
	@AppStorage("cinemaEnvironment") private var environment: CinemaEnvironment = .sarTent
	@State private var world = Entity()
	@State private var backdrop: Entity?
	@State private var panelGrabber = Self.makePanelGrabber()
	/// The point the image was rendered from, kept at the viewer's eyes. The backdrop and the
	/// boards hang from it, so the panels stay over the boards in the image.
	@State private var eyes = Entity()
	@State private var headTracker = CinemaHeadTracker()
	@State private var followHead: EventSubscription?
	@State private var anchors: CinemaAnchors?
	@State private var boards = BoardPanels()

	var body: some View {
		RealityView { content, attachments in
			world.name = "Cinema"
			content.add(world)
			eyes.name = "CinemaEyes"
			world.addChild(eyes)
			if let panel = attachments.entity(for: Attachments.panel) {
				panelGrabber.addChild(panel)
				seat(panel)
				panelGrabber.position = [0.45, 0.85, -0.7]
				world.addChild(panelGrabber)
			}
			followHead = content.subscribe(to: SceneEvents.Update.self) { _ in
				moveEyesToHead()
				placeBoards()
			}
		} update: { _, attachments in
			if let panel = attachments.entity(for: Attachments.panel) {
				seat(panel)
			}
			boards.panels[.teamStatus] = attachments.entity(for: Attachments.teamStatus)
			placeBoards()
		} attachments: {
			Attachment(id: Attachments.panel) {
				CinemaPanel(environment: $environment, isScreenLocked: $appState.cinemaScreenLocked) {
					Task { await dismissImmersiveSpace() }
				}
			}
			if let container, !appState.isDatabaseResetting, anchors?.board(.teamStatus) != nil {
				Attachment(id: Attachments.teamStatus) {
					TeamStatusBoard()
						.id(appState.databaseResetID)
						.modelContainer(container)
						.environmentObject(appState)
						.environmentObject(accessoryManager)
				}
			}
		}
		.task(id: environment) {
			anchors = CinemaAnchors.load(for: environment)
			boards.fitted.removeAll()
			moveEyesToHead()
			let next = await CinemaBackdrop.make(environment)
			backdrop?.removeFromParent()
			eyes.addChild(next)
			backdrop = next
		}
		.task {
			await headTracker.start()
		}
		.onAppear {
			appState.cinemaOpen = true
			appState.cinemaScreenLocked = false
			openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
		}
		.onDisappear {
			headTracker.stop()
			followHead?.cancel()
			followHead = nil
			appState.cinemaOpen = false
			appState.cinemaScreenLocked = false
			// The window may have been closed while the cinema was open. Not when the app went to
			// the background, which closes the cinema too.
			if appState.mainWindowCount == 0, scenePhase != .background {
				openWindow(id: MeshtasticAppleApp.mainWindowID)
			}
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .background {
				Task { await dismissImmersiveSpace() }
			}
		}
		.trackScreen(.cinema)
	}

	/// The board panels SwiftUI has made, kept for the per-frame placement.
	private final class BoardPanels {
		var panels: [CinemaBoard: Entity] = [:]
		var fitted: Set<CinemaBoard> = []
	}

	private enum Attachments {
		static let panel = "panel"
		static let teamStatus = "teamStatus"
	}

	/// Keeps the render's camera at the viewer's eyes. Without head tracking (the simulator),
	/// at the seated eye height the image was rendered from.
	private func moveEyesToHead() {
		if let head = headTracker.headPosition() {
			eyes.position = head
		} else if let anchors {
			eyes.position = [0, anchors.eyeHeight, 0]
		}
	}

	/// Puts each board's panel over its board in the image, scaled to the board. A panel's size
	/// is only known once SwiftUI has laid it out, so this runs every frame until it is.
	private func placeBoards() {
		for (board, panel) in boards.panels {
			guard let anchor = anchors?.board(board) else { continue }
			if panel.parent !== eyes {
				eyes.addChild(panel)
				boards.fitted.remove(board)
			}
			if !boards.fitted.contains(board) {
				let width = panel.visualBounds(relativeTo: panel).extents.x
				guard width > 0 else { continue }
				panel.scale = SIMD3(repeating: anchor.width / width)
				panel.position = anchor.position
				panel.orientation = anchor.orientation
				boards.fitted.insert(board)
			}
		}
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
