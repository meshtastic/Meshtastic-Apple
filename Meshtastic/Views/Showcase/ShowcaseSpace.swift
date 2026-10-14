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

/// Root of the showcase immersive space: the room with the viewer's seat at the origin, the
/// connected radio on the desk, the mesh on the wall rack, a showroom of device models on the
/// shelves, the control panel by the desk, and the card for whatever was tapped. Reads the nodes
/// every few seconds and closes itself when the app goes to the background.
struct ShowcaseSpace: View {
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
	@Environment(\.openWindow) private var openWindow
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@AppStorage("showcaseSeated") private var seated = true
	@State private var scene = ShowcaseSceneController()
	@Query(sort: [SortDescriptor(\DeviceLinkEntity.shortCode)]) private var deviceLinks: [DeviceLinkEntity]

	static let refreshInterval: Duration = .seconds(5)

	private var preset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	var body: some View {
		RealityView { content, attachments in
			let room = await ShowcaseRoom.load()
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
			Task { await scene.loadShowroomIfReady() }
		} update: { _, attachments in
			if let panel = attachments.entity(for: Attachments.controls) {
				placeControls(panel)
			}
			placeCard(attachments.entity(for: Attachments.card))
			placeItemCard(attachments.entity(for: Attachments.itemCard))
		} attachments: {
			Attachment(id: Attachments.controls) {
				ShowcaseControlPanel(scene: scene, seated: $seated) {
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
			if let id = scene.selectedItem, let item = scene.showroom.items.first(where: { $0.id == id }) {
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
			await scene.setShowroomHardware(hardware)
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
		}
		.onAppear {
			appState.showcaseOpen = true
			scene.preset = preset
		}
		.onDisappear {
			appState.showcaseOpen = false
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
				if let item = scene.showroom.item(tappedOn: value.entity) {
					scene.selectedItem = scene.selectedItem == item ? nil : item
					return
				}
				let point = value.convert(value.location3D, from: .local, to: .scene)
				guard let num = scene.node(tappedOn: value.entity, scenePoint: point) else { return }
				scene.selected = scene.selected == num ? nil : num
			}
	}

	/// Over the front of the desk's left side, in front of the lamp, turned to face the seat.
	/// Higher when standing, where the viewer is also further back in the world.
	private func placeControls(_ panel: Entity) {
		let position = SIMD3<Float>(-0.4, seated ? 0.95 : 1.25, -0.4)
		let eye = ShowcaseRoomGeometry.seatedEye + (seated ? .zero : SIMD3<Float>(0, 0.4, ShowcaseSceneController.standingSetback))
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

	private func placeItemCard(_ card: Entity?) {
		guard let card else { return }
		guard let id = scene.selectedItem, let position = scene.showroom.cardPosition(forItem: id) else {
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
