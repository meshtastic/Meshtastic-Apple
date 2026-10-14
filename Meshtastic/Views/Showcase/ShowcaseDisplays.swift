//
//  ShowcaseDisplays.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import MeshtasticProtobufs
import OSLog
import RealityKit
import SwiftUI

/// Marks a model in the showroom, so a tap on any of its parts finds the item.
struct ShowcaseItemComponent: Component {
	let itemID: String
}

/// The shelves' showroom: a real-size model of each device we have one for, one maker per shelf.
/// They are examples of the devices, not nodes on the mesh. A hand can pick one up and turn it
/// over; let go and it goes back on the shelf.
@MainActor @Observable
final class ShowcaseDisplays {
	@ObservationIgnored let root = Entity()
	/// Each loaded model as it was in its file; shelf items use it directly, the desk a clone.
	@ObservationIgnored private var templates: [String: Entity] = [:]
	/// Where each shelf model stands, and its height, in the world's space.
	@ObservationIgnored private var placements: [String: (position: SIMD3<Float>, height: Float)] = [:]
	@ObservationIgnored private var hardware: [ShowcaseHardwareRecord] = []
	@ObservationIgnored private let models = ShowcaseCatalog.bundledModels()

	/// The shelves' models, once loaded.
	private(set) var items: [ShowcaseItem] = []

	init() {
		ShowcaseItemComponent.registerComponent()
		root.name = "Showroom"
	}

	/// A loaded model, as it was in its file.
	func template(named name: String) -> Entity? {
		templates[name]
	}

	/// The loaded model for a node's hardware, if there is one. Nodes store the hardware as its
	/// enum case's name, uppercased, which gives back the number.
	func modelName(forHardwareSlug slug: String?) -> String? {
		let number = slug.flatMap { slug in HardwareModel.allCases.first { String(describing: $0).uppercased() == slug }?.rawValue }
		guard let name = ShowcaseCatalog.modelName(forHardwareSlug: slug, number: number, models: models, hardware: hardware),
			  templates[name] != nil else { return nil }
		return name
	}

	/// Loads every bundled model with a device in the catalog and stands them on the shelves, one
	/// maker per shelf, spread along it. `receiveLight` gives each model the room's light.
	func load(room: ShowcaseRoom, hardware: [ShowcaseHardwareRecord], receiveLight: (Entity) -> Void) async {
		guard items.isEmpty else { return }
		self.hardware = hardware
		let catalog = ShowcaseCatalog.items(models: models, hardware: hardware)
		for item in catalog {
			guard let url = Bundle.main.url(forResource: item.id, withExtension: "usdz") else { continue }
			do {
				templates[item.id] = try await Entity(contentsOf: url)
			} catch {
				Logger.services.error("📻 [Showcase] Model \(item.id, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
			}
		}
		let loaded = catalog.filter { templates[$0.id] != nil }
		for vendor in ShowcaseVendor.allCases {
			let shelfItems = loaded.filter { $0.vendor == vendor }
			guard !shelfItems.isEmpty else { continue }
			let shelf = room.pose(ShowcaseAnchor.shelves[min(vendor.shelf, ShowcaseAnchor.shelves.count - 1)])
			var stands: [ShowroomStand] = []
			for item in shelfItems {
				guard let model = templates[item.id] else { continue }
				let holder = Entity()
				holder.name = "showroom-\(item.id)"
				let width = model.visualBounds(relativeTo: nil).extents.x
				let height = Self.stand(model, in: holder)
				model.components.set(ShowcaseItemComponent(itemID: item.id))
				model.components.set(Self.accessibility(for: item))
				receiveLight(model)
				stands.append(ShowroomStand(item: item, holder: holder, width: width, height: height))
			}
			let centers = ShowcaseShelfPacking.centers(widths: stands.map(\.width), length: ShowcaseRoomGeometry.shelfLength)
			for (stand, x) in zip(stands, centers) {
				let position = shelf.position + shelf.orientation.act(SIMD3(x, 0, 0))
				stand.holder.position = position
				stand.holder.orientation = shelf.orientation
				root.addChild(stand.holder)
				placements[stand.item.id] = (position, stand.height)
			}
		}
		items = loaded
		Logger.services.info("📻 [Showcase] Showroom: \(loaded.count, privacy: .public) models on the shelves")
	}

	private struct ShowroomStand {
		let item: ShowcaseItem
		let holder: Entity
		let width: Float
		let height: Float
	}

	/// Stands a model in `holder` on its base, centered over the holder's origin, and lets a hand
	/// pick it up. Returns its height.
	@discardableResult
	static func stand(_ model: Entity, in holder: Entity) -> Float {
		model.transform = .identity
		let bounds = model.visualBounds(relativeTo: model)
		model.position = [-bounds.center.x, -bounds.min.y, -bounds.center.z]
		holder.addChild(model)
		makeHoldable(model, bounds: bounds)
		return bounds.extents.y
	}

	/// Pinch to pick it up and turn it over at real size; let go and it goes back where it was.
	private static func makeHoldable(_ model: Entity, bounds: RealityKit.BoundingBox) {
		let shape = ShapeResource.generateBox(size: bounds.extents + SIMD3(repeating: 0.01)).offsetBy(translation: bounds.center)
		ManipulationComponent.configureEntity(model, hoverEffect: .spotlight(.default), allowedInputTypes: .all, collisionShapes: [shape])
		var manipulation = model.components[ManipulationComponent.self] ?? ManipulationComponent()
		manipulation.releaseBehavior = .reset
		manipulation.dynamics.scalingBehavior = .none
		model.components.set(manipulation)
	}

	private static func accessibility(for item: ShowcaseItem) -> AccessibilityComponent {
		var component = AccessibilityComponent()
		component.isAccessibilityElement = true
		component.traits = [.button]
		component.label = LocalizedStringResource(stringLiteral: item.title)
		component.value = LocalizedStringResource("Made by \(item.vendor.rawValue)", comment: "Showcase: VoiceOver value for a model on the shelf; the argument is the maker")
		return component
	}

	/// The showroom model under a tap.
	func item(tappedOn entity: Entity) -> String? {
		var current: Entity? = entity
		while let candidate = current {
			if let component = candidate.components[ShowcaseItemComponent.self] { return component.itemID }
			current = candidate.parent
		}
		return nil
	}

	/// Where a model's card goes: above it on its shelf, a little toward the viewer.
	func cardPosition(forItem id: String) -> SIMD3<Float>? {
		guard let placement = placements[id] else { return nil }
		return placement.position + [0, placement.height + 0.09, 0.12]
	}
}
#endif
