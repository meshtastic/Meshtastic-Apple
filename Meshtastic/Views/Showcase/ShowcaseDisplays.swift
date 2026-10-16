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

	/// Loads every bundled model with a device in the catalog and stands each on a clear stand
	/// along its maker's row of the display tables. `receiveLight` gives each model the room's light.
	func load(room: ShowcaseRoom, hardware: [ShowcaseHardwareRecord], receiveLight: (Entity) -> Void) async {
		guard items.isEmpty else { return }
		let catalog = ShowcaseCatalog.items(models: models, hardware: hardware)
		for item in catalog {
			guard let url = Bundle.main.url(forResource: item.id, withExtension: "usdz") else { continue }
			do {
				let model = try await Entity(contentsOf: url)
				if Self.matte(model) == 0 {
					Logger.services.warning("📻 [Showcase] Model \(item.id, privacy: .public) has no materials the showcase can soften")
				}
				templates[item.id] = model
			} catch {
				Logger.services.error("📻 [Showcase] Model \(item.id, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
			}
		}
		let loaded = catalog.filter { templates[$0.id] != nil }
		// Makers that share a row stand one after the other, front of the room first.
		var rows: [(row: ShowcaseDisplayRow, vendors: [ShowcaseVendor])] = []
		for vendor in ShowcaseVendor.allCases.sorted(by: { $0.displayOrder < $1.displayOrder }) where loaded.contains(where: { $0.vendor == vendor }) {
			if let index = rows.firstIndex(where: { $0.row == vendor.row }) {
				rows[index].vendors.append(vendor)
			} else {
				rows.append((vendor.row, [vendor]))
			}
		}
		for (row, vendors) in rows {
			let table = room.pose(row.table)
			// Each maker's run starts with its brand card, which takes a place in the row like a model.
			var slots: [DisplaySlot] = []
			for vendor in vendors {
				slots.append(.brand(vendor))
				for item in loaded where item.vendor == vendor {
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
					slots.append(.stand(DisplayStand(item: item, holder: holder, width: width + Self.standMargin, height: height, depth: depth)))
				}
			}
			let centers = ShowcaseRowPacking.centers(widths: slots.map(\.width), length: row.length)
			for (index, (slot, x)) in zip(slots, centers).enumerated() {
				let local = SIMD3<Float>(row.centerX + x, row.height, row.depthOffset)
				let position = table.position + table.orientation.act(local)
				switch slot {
				case .brand(let vendor):
					guard let card = await ShowcaseDeviceMeshes.brandCard(for: vendor) else { continue }
					let holder = Entity()
					holder.name = "brand-\(vendor.rawValue)"
					holder.position = position
					holder.orientation = table.orientation
					holder.addChild(card)
					receiveLight(holder)
					root.addChild(holder)
				case .stand(let stand):
					stand.holder.position = position
					stand.holder.orientation = table.orientation
					root.addChild(stand.holder)
					placements[stand.item.id] = (position, stand.height)
					// As wide as the space to the nearer neighbor allows, up to the "Your radio" card's,
					// and as far in front as that card, or further for a deep stand.
					let room = [index > 0 ? x - centers[index - 1] : row.length, index + 1 < centers.count ? centers[index + 1] - x : row.length].min() ?? row.length
					let width = min(ShowcaseDeviceMeshes.placardSize.x, room - Self.placardGap)
					let distance = max(ShowcaseDeviceMeshes.placardDistance, stand.depth / 2 + Self.placardGap * 2)
					if let placard = await ShowcaseDeviceMeshes.placard(for: stand.item, width: width, inFrontBy: distance) {
						stand.holder.addChild(placard)
					}
				}
			}
		}
		items = loaded
		Logger.services.info("📻 [Showcase] \(loaded.count, privacy: .public) models on the tables")
	}

	/// A place along a row: a maker's brand card, or a model on its stand.
	private enum DisplaySlot {
		case brand(ShowcaseVendor)
		case stand(DisplayStand)

		var width: Float {
			switch self {
			case .brand: ShowcaseDeviceMeshes.brandCardSize.x + ShowcaseDisplays.placardGap * 2
			case .stand(let stand): stand.width
			}
		}
	}

	private struct DisplayStand {
		let item: ShowcaseItem
		let holder: Entity
		let width: Float
		let height: Float
		let depth: Float
	}

	/// The space kept between a placard and its neighbors, and between it and its stand.
	static let placardGap: Float = 0.012

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
		makeHoldable(model, bounds: grabBounds(of: model) ?? bounds)
		return bounds.extents.y + standThickness
	}

	/// Takes the shine off a model's surfaces: under the store lights the files' glossy plastic and
	/// metal read as glare. Only the showcase's copy changes; the files stay as they are.
	/// Returns how many materials it softened.
	@discardableResult
	static func matte(_ entity: Entity) -> Int {
		var softened = 0
		if var model = entity.components[ModelComponent.self] {
			model.materials = model.materials.map { material in
				guard var material = material as? PhysicallyBasedMaterial else { return material }
				softened += 1
				material.roughness = .init(floatLiteral: max(material.roughness.scale, 0.85))
				material.metallic = .init(floatLiteral: material.metallic.scale * 0.3)
				material.specular = .init(floatLiteral: 0.2)
				return material
			}
			entity.components.set(model)
		}
		for child in entity.children {
			softened += matte(child)
		}
		return softened
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

	/// The model's body without its antennas, in its own space: what a pinch grabs and the spotlight
	/// lights. A tall antenna would otherwise stand in front of the models behind it and catch their
	/// pinches. Antenna parts are the ones the model generator names Antenna or Whip.
	static func grabBounds(of model: Entity) -> RealityKit.BoundingBox? {
		var result: RealityKit.BoundingBox?
		var pending = [model]
		while let entity = pending.popLast() {
			pending += entity.children
			let name = entity.name.lowercased()
			guard entity.components.has(ModelComponent.self), !name.contains("antenna"), !name.contains("whip") else { continue }
			let bounds = entity.visualBounds(recursive: false, relativeTo: model)
			guard !bounds.isEmpty else { continue }
			result = result.map { $0.union(bounds) } ?? bounds
		}
		return result
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
		component.value = LocalizedStringResource("Made by \(item.vendor.name)", comment: "Showcase: VoiceOver value for a model on a display table; the argument is the maker")
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

	/// Where a model's card goes: above it on its table, a little toward the viewer.
	func cardPosition(forItem id: String) -> SIMD3<Float>? {
		guard let placement = placements[id] else { return nil }
		return placement.position + [0, placement.height + 0.09, 0.12]
	}
}
#endif
