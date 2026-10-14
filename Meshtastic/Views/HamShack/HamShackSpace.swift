//
//  HamShackSpace.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import OSLog
import RealityKit
import SwiftData
import SwiftUI

/// Root of the ham shack immersive space: the room with the viewer's seat at the origin, the mesh's
/// radios on the desk, shelves and wall rack, the control panel by the desk, and the card for a
/// tapped radio. Reads the nodes every few seconds and closes itself when the app goes to the
/// background.
struct HamShackSpace: View {
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
	@Environment(\.openWindow) private var openWindow
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@AppStorage("hamShackSeated") private var seated = true
	@State private var scene = ShackSceneController()

	static let refreshInterval: Duration = .seconds(5)

	private var preset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	var body: some View {
		RealityView { content, attachments in
			let room = await ShackRoom.load()
			scene.install(room: room)
			scene.setSeated(seated)
			content.add(scene.world)
			if let panel = attachments.entity(for: Attachments.controls) {
				placeControls(panel)
				scene.world.addChild(panel)
			}
			scene.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
				scene.step(deltaTime: event.deltaTime)
			}
		} update: { _, attachments in
			if let panel = attachments.entity(for: Attachments.controls) {
				placeControls(panel)
			}
			placeCard(attachments.entity(for: Attachments.card))
		} attachments: {
			Attachment(id: Attachments.controls) {
				ShackControlPanel(scene: scene, seated: $seated) {
					Task { await dismissImmersiveSpace() }
				}
			}
			if let selected = scene.selected, let node = scene.nodesByNum[selected] {
				Attachment(id: Attachments.card) {
					ShackNodeCard(node: node, isOnline: scene.isOnline(selected), preset: preset) {
						showInMainWindow(node.id)
					} onClose: {
						scene.selected = nil
					}
				}
			}
		}
		.gesture(tap)
		.task(id: accessoryManager.activeDeviceNum) {
			// Made off the main thread: a model actor made on it runs its fetches there too.
			let container = context.container
			let reader = await Task.detached { ShackSnapshotReader(modelContainer: container) }.value
			while !Task.isCancelled {
				let result = await reader.read(connectedNodeNum: accessoryManager.activeDeviceNum)
				scene.apply(result)
				try? await Task.sleep(for: Self.refreshInterval)
			}
		}
		.onReceive(accessoryManager.packetEvents) { event in
			scene.handle(event)
		}
		.onChange(of: accessoryManager.isHighMeshTraffic, initial: true) { _, isHigh in
			scene.isHighTraffic = isHigh
		}
		.onChange(of: reduceMotion, initial: true) { _, reduce in
			scene.reduceMotion = reduce
		}
		.onChange(of: seated) { _, isSeated in
			scene.setSeated(isSeated)
		}
		.onAppear {
			appState.hamShackOpen = true
			scene.preset = preset
		}
		.onDisappear {
			appState.hamShackOpen = false
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .background {
				Task { await dismissImmersiveSpace() }
			}
		}
		.trackScreen(.hamShack)
	}

	private enum Attachments {
		static let controls = "controls"
		static let card = "card"
	}

	private var tap: some Gesture {
		SpatialTapGesture()
			.targetedToAnyEntity()
			.onEnded { value in
				let point = value.convert(value.location3D, from: .local, to: .scene)
				guard let num = scene.node(tappedOn: value.entity, scenePoint: point) else { return }
				scene.selected = scene.selected == num ? nil : num
			}
	}

	/// Over the front of the desk's left side, in front of the lamp, turned to face the seat.
	/// Higher when standing, where the viewer is also further back in the world.
	private func placeControls(_ panel: Entity) {
		let position = SIMD3<Float>(-0.4, seated ? 0.95 : 1.25, -0.4)
		let eye = ShackRoomGeometry.seatedEye + (seated ? .zero : SIMD3<Float>(0, 0.4, ShackSceneController.standingSetback))
		panel.look(at: eye, from: position, relativeTo: scene.world, forward: .positiveZ)
	}

	private func placeCard(_ card: Entity?) {
		guard let card else { return }
		guard let selected = scene.selected, let position = scene.cardPosition(for: selected) else {
			card.isEnabled = false
			return
		}
		if card.parent !== scene.world {
			card.components.set(BillboardComponent())
			scene.world.addChild(card)
		}
		card.position = position
		card.isEnabled = true
	}

	/// Hands the node to the main window, opening one if there is none.
	private func showInMainWindow(_ nodeNum: Int64) {
		guard let url = URL(string: "meshtastic:///nodes?nodenum=\(nodeNum)") else { return }
		appState.pendingRoute = PendingRoute(url: url, bringForward: true)
		if appState.mainWindowCount == 0 {
			openWindow(id: MeshtasticAppleApp.mainWindowID)
		}
	}
}
#endif
