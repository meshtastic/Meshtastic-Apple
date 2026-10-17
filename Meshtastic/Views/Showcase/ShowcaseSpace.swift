//
//  ShowcaseSpace.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import OSLog
import RealityKit
import SwiftData
import SwiftUI

/// Root of the hardware showcase immersive space: the room with the viewer's seat at the origin,
/// device models and the connected radio on the display tables, the mesh on the wall rack, the
/// control panel by the front table, and the card for whatever was tapped. Reads the nodes every
/// few seconds and closes itself when the app goes to the background.
struct ShowcaseSpace: View {
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
	@Environment(\.openWindow) private var openWindow
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@AppStorage("showcaseSeated") private var seated = true
	@State private var scene = ShowcaseSceneController()
	/// The grab bar under the control panel; the panel rides on it.
	@State private var controlsGrabber = Self.makeControlsGrabber()
	@Query(sort: [SortDescriptor(\DeviceLinkEntity.shortCode)]) private var deviceLinks: [DeviceLinkEntity]

	static let refreshInterval: Duration = .seconds(5)
	static let showsCardOnGrab = false

	private var preset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	var body: some View {
		RealityView { content, attachments in
			let room = await ShowcaseRoom.load()
			scene.install(room: room)
			scene.setSeated(seated)
			content.add(scene.world)
			if let panel = attachments.entity(for: Attachments.controls) {
				controlsGrabber.addChild(panel)
				seat(panel)
				scene.world.addChild(controlsGrabber)
				placeControls()
			}
			scene.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
				scene.step(deltaTime: event.deltaTime)
			}
			// Picking a model up with the system grab opens its card (a tap can't: the grab takes
			// the pinch first). Off for now; the placard in front of each model names it.
			if Self.showsCardOnGrab {
				scene.grabSubscription = content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
					if let item = scene.displays.item(tappedOn: event.entity) {
						scene.selectedItem = item
					}
				}
			}
			Task { await scene.loadDisplaysIfReady() }
		} update: { _, attachments in
			// Before placing cards, so they follow a seated/standing switch.
			scene.setSeated(seated)
			if let panel = attachments.entity(for: Attachments.controls) {
				seat(panel)
			}
			placeCard(attachments.entity(for: Attachments.card))
			placeItemCard(attachments.entity(for: Attachments.itemCard))
		} attachments: {
			Attachment(id: Attachments.controls) {
				ShowcaseControlPanel(scene: scene, seated: $seated, isAppShowing: appState.mainWindowCount > 0) {
					if appState.mainWindowCount > 0 {
						dismissWindow(id: MeshtasticAppleApp.mainWindowID)
					} else {
						openWindow(id: MeshtasticAppleApp.mainWindowID)
					}
				} onLeave: {
					// The window first: once the room has closed, this view can't open it.
					if appState.mainWindowCount == 0 {
						openWindow(id: MeshtasticAppleApp.mainWindowID)
					}
					Task { await dismissImmersiveSpace() }
				}
			}
			if let selected = scene.selected, let node = scene.nodesByNum[selected] {
				Attachment(id: Attachments.card) {
					ShowcaseNodeCard(node: node, isOnline: scene.isOnline(selected), preset: preset) {
						showInMainWindow(node.id)
					} onClose: {
						scene.selected = nil
					}
				}
			}
			if let id = scene.selectedItem, let item = scene.displays.items.first(where: { $0.id == id }) {
				Attachment(id: Attachments.itemCard) {
					ShowcaseModelCard(item: item, links: links(for: item)) {
						scene.selectedItem = nil
					}
				}
			}
		}
		.gesture(tap)
		.task {
			// The context is read here, not in the RealityView's make, where SwiftData traps.
			let hardware = await ShowcaseCatalog.hardware(in: context.container)
			await scene.setDisplayHardware(hardware)
			#if DEBUG
			// `--meshtastic-showcase-card <model>` opens a model's card once the tables are set.
			let arguments = CommandLine.arguments
			if let index = arguments.firstIndex(of: "--meshtastic-showcase-card"), index + 1 < arguments.count {
				while scene.displays.items.isEmpty, !Task.isCancelled {
					try? await Task.sleep(for: .milliseconds(250))
				}
				scene.selectedItem = arguments[index + 1]
			}
			#endif
		}
		.task(id: accessoryManager.activeDeviceNum) {
			// Made off the main thread: a model actor made on it runs its fetches there too.
			let container = context.container
			let reader = await Task.detached { ShowcaseSnapshotReader(modelContainer: container) }.value
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
			placeControls()
		}
		.onAppear {
			appState.showcaseOpen = true
			scene.preset = preset
			// The room is the app while it's open; the panel brings the window back.
			dismissWindow(id: MeshtasticAppleApp.mainWindowID)
		}
		.onDisappear {
			appState.showcaseOpen = false
			// Stops the per-frame updates; the closure holds the scene.
			scene.updateSubscription?.cancel()
			scene.updateSubscription = nil
			scene.grabSubscription?.cancel()
			scene.grabSubscription = nil
			// Leaving with the Digital Crown would otherwise leave the app with no window (the
			// panel's Leave opens it first). Not when the app went to the background, which
			// closes the room too.
			if appState.mainWindowCount == 0, scenePhase != .background {
				openWindow(id: MeshtasticAppleApp.mainWindowID)
			}
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .background {
				Task { await dismissImmersiveSpace() }
			}
		}
		.trackScreen(.showcase)
	}

	private enum Attachments {
		static let controls = "controls"
		static let card = "card"
		static let itemCard = "itemCard"
	}

	private var tap: some Gesture {
		SpatialTapGesture()
			.targetedToAnyEntity()
			.onEnded { value in
				if let item = scene.displays.item(tappedOn: value.entity) {
					scene.selectedItem = scene.selectedItem == item ? nil : item
					return
				}
				let point = value.convert(value.location3D, from: .local, to: .scene)
				guard let num = scene.node(tappedOn: value.entity, scenePoint: point) else { return }
				scene.selected = scene.selected == num ? nil : num
			}
	}

	/// In front of the front table's left end, higher when standing. Puts back a panel that was
	/// moved, too.
	private func placeControls() {
		controlsGrabber.setPosition(SIMD3<Float>(-0.75, seated ? 0.92 : 1.22, -0.7), relativeTo: scene.world)
	}

	/// The panel sits just above the grab bar, however tall it is.
	private func seat(_ panel: Entity) {
		let height = panel.visualBounds(relativeTo: panel).extents.y
		panel.position = [0, height / 2 + Self.grabberGap, 0]
	}

	private static let grabberGap: Float = 0.012

	/// A bar like a window's: pinch and drag it to move the control panel. It and the panel keep
	/// facing the viewer.
	private static func makeControlsGrabber() -> Entity {
		var material = UnlitMaterial(color: .white)
		material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
		let bar = ModelEntity(mesh: .generateBox(width: 0.08, height: 0.008, depth: 0.008, cornerRadius: 0.004), materials: [material])
		bar.name = "ControlsGrabber"
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
		accessibility.label = LocalizedStringResource("Move the control panel", comment: "Showcase: VoiceOver label for the bar under the control panel that moves it")
		bar.components.set(accessibility)
		return bar
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

	private func placeItemCard(_ card: Entity?) {
		guard let card else { return }
		guard let id = scene.selectedItem, let position = scene.cardPosition(forItem: id) else {
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

	/// Where to buy the model's devices: the maker's own links first, then shops that ship to the
	/// viewer's region, as on a node's detail screen.
	private func links(for item: ShowcaseItem) -> [ShowcaseModelCard.Link] {
		let region = Locale.current.region?.identifier ?? ""
		return deviceLinks
			.filter { link in item.targets.contains { link.isVisible(forTarget: $0, userRegion: region) } }
			.sorted { lhs, rhs in
				if lhs.isMarketplace != rhs.isMarketplace { return !lhs.isMarketplace }
				return (lhs.linkDescription ?? lhs.shortCode) < (rhs.linkDescription ?? rhs.shortCode)
			}
			.compactMap { link in
				URL(string: "https://msh.to/\(link.shortCode)").map {
					ShowcaseModelCard.Link(id: link.shortCode, title: link.linkDescription ?? link.shortCode, isVendor: link.isVendor, url: $0)
				}
			}
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
