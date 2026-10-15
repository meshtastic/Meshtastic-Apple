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

/// Marks a model on a display table, so a tap on any of its parts finds the item.
struct ShowcaseItemComponent: Component {
	let itemID: String
}

/// The display tables: a real-size model of each device we have one for, one maker per row.
/// They are examples of the devices, not nodes on the mesh. A hand can pick one up and turn it
/// over; let go and it goes back on its stand.
@MainActor @Observable
final class ShowcaseDisplays {
	@ObservationIgnored let root = Entity()
	/// Each loaded model as it was in its file; the tables use it directly, the connected radio a clone.
	@ObservationIgnored private var templates: [String: Entity] = [:]
	/// Where each model stands, and its height, in the world's space.
	@ObservationIgnored private var placements: [String: (position: SIMD3<Float>, height: Float)] = [:]
	/// Where each model's placard stands. Set before `items`, so it's there when the placards are made.
	@ObservationIgnored private(set) var placards: [String: ShowcasePlacardSpot] = [:]
	@ObservationIgnored private var hardware: [ShowcaseHardwareRecord] = []
	@ObservationIgnored private let models = ShowcaseCatalog.bundledModels()

	/// The shelves' models, once loaded.
	private(set) var items: [ShowcaseItem] = []

	init() {
		ShowcaseItemComponent.registerComponent()
		root.name = "Displays"
	}

	/// The model standing on a table for an item.
	func model(for id: String) -> Entity? {
		templates[id]
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

	/// Loads every bundled model with a device in the catalog and stands each on a clear stand
	/// along its maker's row of the display tables. `receiveLight` gives each model the room's light.
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
			let rowItems = loaded.filter { $0.vendor == vendor }
			guard !rowItems.isEmpty else { continue }
			let row = vendor.row
			let table = room.pose(row.table)
			var stands: [DisplayStand] = []
			for item in rowItems {
				guard let model = templates[item.id] else { continue }
				let holder = Entity()
				holder.name = "display-\(item.id)"
				let width = model.visualBounds(relativeTo: nil).extents.x
				let height = Self.stand(model, in: holder)
				let depth = max(model.visualBounds(relativeTo: holder).extents.z + Self.standMargin * 2, 0.05)
				model.components.set(ShowcaseItemComponent(itemID: item.id))
				model.components.set(Self.accessibility(for: item))
				// The holder, so the clear stand gets the room's light too.
				receiveLight(holder)
				stands.append(DisplayStand(item: item, holder: holder, width: width + Self.standMargin, height: height, depth: depth))
			}
			let centers = ShowcaseRowPacking.centers(widths: stands.map(\.width), length: row.length)
			let tilt = simd_quatf(angle: -Self.placardTilt, axis: [1, 0, 0])
			for (index, (stand, x)) in zip(stands, centers).enumerated() {
				let local = SIMD3<Float>(row.centerX + x, row.height, row.depthOffset)
				let position = table.position + table.orientation.act(local)
				stand.holder.position = position
				stand.holder.orientation = table.orientation
				root.addChild(stand.holder)
				placements[stand.item.id] = (position, stand.height)
				// As wide as the space to the nearer neighbor allows, up to the most a placard is.
				let room = [index > 0 ? x - centers[index - 1] : row.length, index + 1 < centers.count ? centers[index + 1] - x : row.length].min() ?? row.length
				let front = local + [0, 0, stand.depth / 2 + Self.placardGap]
				placards[stand.item.id] = ShowcasePlacardSpot(
					base: table.position + table.orientation.act(front),
					orientation: table.orientation * tilt,
					size: [min(Self.placardSize.x, room - Self.placardGap), Self.placardSize.y]
				)
			}
		}
		items = loaded
		Logger.services.info("📻 [Showcase] \(loaded.count, privacy: .public) models on the tables")
	}

	private struct DisplayStand {
		let item: ShowcaseItem
		let holder: Entity
		let width: Float
		let height: Float
		let depth: Float
	}

	/// A placard's largest size in meters, how far in front of its stand it stands, and how far
	/// it leans back, so it reads from a chair.
	static let placardSize = SIMD2<Float>(0.1, 0.055)
	static let placardGap: Float = 0.012
	static let placardTilt: Float = .pi / 9

	/// The clear stand's thickness, and how far it reaches past the model on each side.
	static let standThickness: Float = 0.006
	static let standMargin: Float = 0.012

	/// Stands a model on a clear stand in `holder`, centered over the holder's origin, and lets a
	/// hand pick it up. Returns its height, stand included.
	@discardableResult
	static func stand(_ model: Entity, in holder: Entity) -> Float {
		model.transform = .identity
		let bounds = model.visualBounds(relativeTo: model)
		model.position = [-bounds.center.x, standThickness - bounds.min.y, -bounds.center.z]
		let base = ModelEntity(
			mesh: .generateBox(
				width: bounds.extents.x + standMargin,
				height: standThickness,
				depth: max(bounds.extents.z + standMargin * 2, 0.05),
				cornerRadius: 0.002
			),
			materials: [clearAcrylic]
		)
		base.name = "stand"
		base.position = [0, standThickness / 2, 0]
		holder.addChild(base)
		holder.addChild(model)
		model.components.set(ShowcaseHomeComponent(transform: model.transform))
		makeHoldable(model, bounds: bounds)
		return bounds.extents.y + standThickness
	}

	/// Clear acrylic, like a store's display stands.
	private static let clearAcrylic: PhysicallyBasedMaterial = {
		var material = PhysicallyBasedMaterial()
		material.baseColor = .init(tint: .white)
		material.roughness = 0.05
		material.clearcoat = .init(floatLiteral: 1)
		material.blending = .transparent(opacity: .init(floatLiteral: 0.22))
		return material
	}()

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
		component.value = LocalizedStringResource("Made by \(item.vendor.rawValue)", comment: "Showcase: VoiceOver value for a model on a display table; the argument is the maker")
		return component
	}

	/// The displayed model under a tap.
	func item(tappedOn entity: Entity) -> String? {
		var current: Entity? = entity
		while let candidate = current {
			if let component = candidate.components[ShowcaseItemComponent.self] { return component.itemID }
			current = candidate.parent
		}
		return nil
	}

	/// The placard's center for a model: its bottom edge on the table at `base`, leaning back.
	func placardCenter(forItem id: String) -> SIMD3<Float>? {
		guard let spot = placards[id] else { return nil }
		return spot.base + spot.orientation.act([0, spot.size.y / 2, 0])
	}

	/// Where a model's card goes: above it on its table, a little toward the viewer.
	func cardPosition(forItem id: String) -> SIMD3<Float>? {
		guard let placement = placements[id] else { return nil }
		return placement.position + [0, placement.height + 0.09, 0.12]
	}
}
/// Where a model's placard stands on its table, which way it faces, and its size in meters.
struct ShowcasePlacardSpot: Equatable {
	let base: SIMD3<Float>
	let orientation: simd_quatf
	let size: SIMD2<Float>
}
#endif
