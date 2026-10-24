//
//  CinemaSpace.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
#if os(visionOS)
import RealityKit
import SwiftUI

/// Root of the cinema immersive space: an environment around the viewer and the app's windows,
/// and a small panel to change the environment or leave. The app stays in its own window, which
/// can be moved back and made bigger like a screen; a window drawn inside the space can't show the
/// tab bar or sheets.
struct CinemaSpace: View {
	@EnvironmentObject private var appState: AppState
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
	@Environment(\.openWindow) private var openWindow
	@AppStorage("cinemaEnvironment") private var environment: CinemaEnvironment = .sarTent
	@State private var world = Entity()
	@State private var backdrop: Entity?
	@State private var panelGrabber = Self.makePanelGrabber()

	var body: some View {
		RealityView { content, attachments in
			world.name = "Cinema"
			content.add(world)
			if let panel = attachments.entity(for: Attachments.panel) {
				panelGrabber.addChild(panel)
				seat(panel)
				panelGrabber.position = [0.45, 0.85, -0.7]
				world.addChild(panelGrabber)
			}
		} update: { _, attachments in
			if let panel = attachments.entity(for: Attachments.panel) {
				seat(panel)
			}
		} attachments: {
			Attachment(id: Attachments.panel) {
				CinemaPanel(environment: $environment, isScreenLocked: $appState.cinemaScreenLocked) {
					Task { await dismissImmersiveSpace() }
				}
			}
		}
		.task(id: environment) {
			let next = await CinemaBackdrop.make(environment)
			backdrop?.removeFromParent()
			world.addChild(next)
			backdrop = next
		}
		.onAppear {
			appState.cinemaOpen = true
			appState.cinemaScreenLocked = false
		}
		.onDisappear {
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

	private enum Attachments {
		static let panel = "panel"
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
