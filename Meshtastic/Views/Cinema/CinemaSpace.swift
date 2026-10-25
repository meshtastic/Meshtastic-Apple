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
/// and a small panel to change the environment or leave. The app stays in its own real window, so
/// the tab bar, sheets and alerts work as usual; a window drawn inside the space can't show them.
/// Nothing can fix a window in place, so the wall comes to the window: the tent turns so its front
/// wall faces the window, and `CinemaWindowMount` sets the window into that wall with a black
/// frame, the wall drawn at the window's own depth. The 3D map opens beside it. The tent's
/// whiteboard shows the live team roster.
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
	/// The point the image was rendered from. Until the window is placed it sits at the seated eye
	/// height, turned so the image's center is in front; then the mount puts it at the viewer's eye,
	/// turned so the front wall faces the window. The backdrop, the boards and the front wall hang
	/// from it, so one turn moves them all.
	@State private var stage = Entity()
	@State private var mount = CinemaWindowMount()
	@State private var fitBoards: EventSubscription?
	@State private var anchors: CinemaAnchors?
	@State private var boards = BoardPanels()

	var body: some View {
		// Read here so a new window pose runs the update closure.
		let windowPose = appState.cinemaWindow.pose
		RealityView { content, attachments in
			world.name = "Cinema"
			content.add(world)
			stage.name = "CinemaStage"
			world.addChild(stage)
			world.addChild(mount.frame)
			if let panel = attachments.entity(for: Attachments.panel) {
				panelGrabber.addChild(panel)
				seat(panel)
				panelGrabber.position = [0.45, 0.85, -0.7]
				world.addChild(panelGrabber)
			}
			// A panel's size is only known once SwiftUI has laid it out, so boards are fitted on
			// the first frame that has it.
			fitBoards = content.subscribe(to: SceneEvents.Update.self) { event in
				placeBoards()
				mount.update(deltaTime: event.deltaTime, stage: stage)
			}
		} update: { content, attachments in
			if let windowPose {
				let corners = windowPose.corners.map { content.convert($0, from: .immersiveSpace, to: .scene) }
				mount.setWindow(corners: corners, widthPoints: windowPose.size.width)
			} else {
				mount.clearWindow()
			}
			if let panel = attachments.entity(for: Attachments.panel) {
				seat(panel)
			}
			boards.set(attachments.entity(for: Attachments.teamStatus), for: .teamStatus)
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
			stage.position = [0, anchors?.eyeHeight ?? CinemaAnchors.seatedEyeHeight, 0]
			stage.orientation = simd_quatf(angle: environment.frontRotation, axis: [0, 1, 0])
			boards.fitted.removeAll()
			let next = await CinemaBackdrop.make(environment)
			backdrop?.removeFromParent()
			stage.addChild(next)
			backdrop = next
			await mount.setFrontWall(anchors?.frontWall, imageName: environment.imageName, eyeHeight: anchors?.eyeHeight ?? CinemaAnchors.seatedEyeHeight, on: stage)
		}
		.task {
			await mount.start()
		}
		.onAppear {
			appState.cinemaOpen = true
			appState.cinemaScreenLocked = false
			openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
		}
		.onDisappear {
			fitBoards?.cancel()
			fitBoards = nil
			mount.stop()
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

	/// The board panels SwiftUI has made, and which of them are placed.
	private final class BoardPanels {
		var panels: [CinemaBoard: Entity] = [:]
		var fitted: Set<CinemaBoard> = []

		/// Keeps the board's panel, taking the old one out of the scene when SwiftUI drops or
		/// replaces it (a database reset).
		func set(_ panel: Entity?, for board: CinemaBoard) {
			guard panels[board] !== panel else { return }
			panels[board]?.removeFromParent()
			panels[board] = panel
			fitted.remove(board)
		}
	}

	private enum Attachments {
		static let panel = "panel"
		static let teamStatus = "teamStatus"
	}

	/// Puts each board's panel over its board in the image, out by the backdrop so both eyes see it
	/// at the painting's depth, and scaled so it covers the same part of the view.
	private func placeBoards() {
		guard boards.fitted.count < boards.panels.count, let anchors else { return }
		for (board, panel) in boards.panels where !boards.fitted.contains(board) {
			guard let anchor = anchors.board(board) else { continue }
			if panel.parent !== stage {
				stage.addChild(panel)
			}
			let size = panel.visualBounds(relativeTo: panel).extents
			guard size.x > 0, size.y > 0 else { continue }
			let push = anchor.distanceScale(within: CinemaBackdrop.radius * 0.96)
			panel.scale = SIMD3(repeating: push * min(anchor.width / size.x, anchor.height / size.y))
			panel.position = anchor.position * push
			panel.orientation = anchor.orientation
			boards.fitted.insert(board)
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
