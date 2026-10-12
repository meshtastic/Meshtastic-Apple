//
//  SpatialSceneController.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import CoreLocation
import Foundation
import RealityKit
import SwiftUI

struct NodePinComponent: Component {
	let nodeNum: Int64
}

/// The bar on the front edge of the terrain. Dragging it slides the map; dragging anywhere else turns it.
struct GrabHandleComponent: Component {}

/// Owns the entities in the volume and diffs the model's snapshots into them, so the RealityView
/// update closure stays a dispatcher. Everything hangs off `terrainAnchor`, which sits on the
/// volume floor; `model` carries the user's rotation and zoom.
@MainActor
final class SpatialSceneController {
	static let pinRadius: Float = 0.006
	static let stemHeight: Float = 0.03
	static let pinTop: Float = stemHeight + pinRadius * 2
	static let flyHeight: Float = pinTop + 0.03

	let root = Entity()
	let model = Entity()
	let terrainAnchor = Entity()
	let nodesContainer = Entity()
	let linksContainer = Entity()
	let selectionContainer = Entity()
	let trafficContainer = Entity()
	var updateSubscription: EventSubscription?

	private struct Pin {
		let holder: Entity
		let pin: ModelEntity
		let halo: ModelEntity
		var baseGlow: Float
	}

	private static let pinMesh = MeshResource.generateSphere(radius: pinRadius)
	private static let stemMesh = MeshResource.generateCylinder(height: stemHeight, radius: 0.0008)
	private static let haloMesh = MeshResource.generateCylinder(height: 0.0008, radius: 0.014)
	private static let ringMesh = MeshResource.generateCylinder(height: 0.0012, radius: 0.02)
	private static let tetherMesh = MeshResource.generateCylinder(height: 1, radius: 0.0006)
	private static let linkMesh = MeshResource.generateBox(size: [0.0016, 0.0016, 1])
	private static let handleMesh = MeshResource.generateBox(size: [0.08, 0.006, 0.018], cornerRadius: 0.003)

	private var placeholder: ModelEntity
	private let handle: ModelEntity
	private var terrainEntity: ModelEntity?
	private var pins: [Int64: Pin] = [:]
	private var applied: [Int64: SpatialNodeSnapshot] = [:]
	private var appliedPlacementRevision = -1
	private(set) var placement: SpatialPlacement?
	private var labelEntities: [Int64: Entity] = [:]
	private var linkEntities: [String: ModelEntity] = [:]
	private var routeEntities: [ModelEntity] = []
	private let ring: ModelEntity
	private let tether: ModelEntity
	private var detailEntity: Entity?
	private var appliedSelection: Int64?
	private(set) var counterScale: Float = 1

	init() {
		// A flat disk of radius 0.5, scaled to the map once there is one.
		placeholder = ModelEntity(mesh: .generateCylinder(height: 0.001, radius: 0.5), materials: [Self.transparentMaterial(.systemGray, opacity: 0.25)])
		placeholder.name = "placeholder"
		ring = ModelEntity(mesh: Self.ringMesh, materials: [UnlitMaterial(color: .white)])
		tether = ModelEntity(mesh: Self.tetherMesh, materials: [Self.transparentMaterial(.white, opacity: 0.7)])
		ring.isEnabled = false
		tether.isEnabled = false
		handle = ModelEntity(mesh: Self.handleMesh, materials: [Self.transparentMaterial(.white, opacity: 0.85)])
		handle.name = "grab-handle"
		// A collision box bigger than the bar, so it is easy to take hold of.
		handle.components.set(CollisionComponent(shapes: [.generateBox(size: [0.12, 0.03, 0.05])]))
		handle.components.set(InputTargetComponent())
		handle.components.set(HoverEffectComponent())
		handle.components.set(GrabHandleComponent())
		var accessibility = AccessibilityComponent()
		accessibility.isAccessibilityElement = true
		accessibility.label = LocalizedStringResource("Move the map", comment: "VoiceOver label for the spatial map grab handle")
		handle.components.set(accessibility)
		NodePinComponent.registerComponent()
		GrabHandleComponent.registerComponent()
		root.addChild(model)
		model.addChild(terrainAnchor)
		terrainAnchor.addChild(placeholder)
		terrainAnchor.addChild(handle)
		terrainAnchor.addChild(nodesContainer)
		terrainAnchor.addChild(linksContainer)
		terrainAnchor.addChild(selectionContainer)
		terrainAnchor.addChild(trafficContainer)
		selectionContainer.addChild(ring)
		selectionContainer.addChild(tether)
	}

	static func transparentMaterial(_ color: UIColor, opacity: Float) -> UnlitMaterial {
		var material = UnlitMaterial(color: color)
		material.blending = .transparent(opacity: .init(floatLiteral: opacity))
		return material
	}

	static func nodeColor(_ nodeNum: Int64) -> UIColor {
		UIColor(hex: UInt32(truncatingIfNeeded: nodeNum))
	}

	/// Places the terrain origin a little above the volume floor.
	func install(floorY: Float) {
		terrainAnchor.position = [0, floorY + 0.03, 0]
	}

	// MARK: Placement and terrain

	func apply(placement: SpatialPlacement?) {
		guard let placement, placement.revision != self.placement?.revision else { return }
		self.placement = placement
		let radius = placement.diskRadius
		placeholder.scale = [2 * radius, 1, 2 * radius]
		// Just outside the front of the disk, along its edge.
		handle.position = [0, 0.004, radius + 0.03]
	}

	func apply(terrainEntity entity: ModelEntity?, building: Bool) {
		if let entity, entity !== terrainEntity {
			terrainEntity?.removeFromParent()
			terrainAnchor.addChild(entity)
			terrainEntity = entity
		}
		// While a new box builds, the old terrain is in the old frame: show the plane instead.
		let showTerrain = terrainEntity != nil && !building
		terrainEntity?.isEnabled = showTerrain
		placeholder.isEnabled = !showTerrain
	}

	// MARK: Nodes

	func apply(nodes: [SpatialNodeSnapshot]) {
		guard let placement else { return }
		let replaceAll = placement.revision != appliedPlacementRevision
		appliedPlacementRevision = placement.revision
		let now = Date()
		var seen = Set<Int64>()
		for node in nodes {
			seen.insert(node.id)
			let previous = applied[node.id]
			if var pin = pins[node.id] {
				if replaceAll || previous == nil || !Self.samePlace(previous!, node) {
					pin.holder.position = placement.position(node.coordinate)
				}
				if previous == nil || !Self.sameLook(previous!, node) { style(pin, for: node) }
				pin.baseGlow = NodeActivityGlow.baseOpacity(NodeActivityGlow.tier(lastHeard: node.lastHeard, now: now))
				pins[node.id] = pin
			} else {
				var pin = makePin(node)
				pin.holder.position = placement.position(node.coordinate)
				pin.holder.scale = SIMD3(repeating: counterScale)
				pin.baseGlow = NodeActivityGlow.baseOpacity(NodeActivityGlow.tier(lastHeard: node.lastHeard, now: now))
				pins[node.id] = pin
				nodesContainer.addChild(pin.holder)
			}
			applied[node.id] = node
		}
		for (num, pin) in pins where !seen.contains(num) {
			pin.holder.removeFromParent()
			pins[num] = nil
			applied[num] = nil
			labelEntities[num] = nil
		}
	}

	private static func samePlace(_ a: SpatialNodeSnapshot, _ b: SpatialNodeSnapshot) -> Bool {
		a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude && a.altitude == b.altitude
	}

	private static func sameLook(_ a: SpatialNodeSnapshot, _ b: SpatialNodeSnapshot) -> Bool {
		a.isOnline == b.isOnline && a.isFavorite == b.isFavorite && a.isConnectedRadio == b.isConnectedRadio
	}

	private func makePin(_ node: SpatialNodeSnapshot) -> Pin {
		let color = Self.nodeColor(node.id)
		let holder = Entity()
		holder.name = "node-\(node.id)"
		let stem = ModelEntity(mesh: Self.stemMesh, materials: [Self.transparentMaterial(.white, opacity: 0.55)])
		stem.position = [0, Self.stemHeight / 2, 0]
		let pin = ModelEntity(mesh: Self.pinMesh, materials: [UnlitMaterial(color: color)])
		pin.position = [0, Self.stemHeight + Self.pinRadius, 0]
		pin.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.015)]))
		pin.components.set(InputTargetComponent())
		pin.components.set(HoverEffectComponent())
		pin.components.set(NodePinComponent(nodeNum: node.id))
		let halo = ModelEntity(mesh: Self.haloMesh, materials: [UnlitMaterial(color: color)])
		halo.position = [0, 0.0006, 0]
		halo.components.set(OpacityComponent(opacity: 0))
		holder.addChild(stem)
		holder.addChild(pin)
		holder.addChild(halo)
		let result = Pin(holder: holder, pin: pin, halo: halo, baseGlow: 0)
		style(result, for: node)
		return result
	}

	private func style(_ pin: Pin, for node: SpatialNodeSnapshot) {
		let color = Self.nodeColor(node.id)
		let size: Float = node.isConnectedRadio ? 1.5 : (node.isFavorite ? 1.2 : 1)
		pin.pin.scale = SIMD3(repeating: size)
		pin.pin.model?.materials = [UnlitMaterial(color: node.isOnline ? color : color.darker(componentDelta: 0.25))]
		pin.pin.components.set(OpacityComponent(opacity: node.isOnline ? 1 : 0.6))
	}

	func pinPosition(_ nodeNum: Int64) -> SIMD3<Float>? {
		guard let pin = pins[nodeNum] else { return nil }
		return pin.holder.position + [0, Self.pinTop * counterScale, 0]
	}

	func baseGlow(_ nodeNum: Int64) -> Float {
		pins[nodeNum]?.baseGlow ?? 0
	}

	func setHalo(_ nodeNum: Int64, opacity: Float, scale: Float) {
		guard let pin = pins[nodeNum] else { return }
		pin.halo.components.set(OpacityComponent(opacity: opacity))
		pin.halo.scale = SIMD3(scale, 1, scale)
	}

	func forEachPin(_ body: (Int64) -> Void) {
		for num in pins.keys { body(num) }
	}

	// MARK: Labels

	func apply(labels: [Int64], attachments: RealityViewAttachments) {
		let wanted = Set(labels)
		for (num, entity) in labelEntities where !wanted.contains(num) {
			entity.removeFromParent()
			labelEntities[num] = nil
		}
		for num in labels {
			guard let pin = pins[num], let entity = attachments.entity(for: num) else { continue }
			if entity.parent !== pin.holder {
				entity.components.set(BillboardComponent())
				entity.position = [0, Self.pinTop + 0.018, 0]
				pin.holder.addChild(entity)
			}
			labelEntities[num] = entity
		}
	}

	// MARK: Selection

	func apply(selection: Int64?, attachments: RealityViewAttachments) {
		guard let selection, let pin = pins[selection] else {
			ring.isEnabled = false
			tether.isEnabled = false
			detailEntity?.removeFromParent()
			detailEntity = nil
			appliedSelection = nil
			return
		}
		appliedSelection = selection
		let base = pin.holder.position
		ring.position = base + [0, 0.0007, 0]
		ring.scale = SIMD3(repeating: counterScale)
		ring.model?.materials = [UnlitMaterial(color: Self.nodeColor(selection))]
		ring.isEnabled = true
		let top = base + [0, Self.pinTop * counterScale, 0]
		let card = top + [0, 0.11 * counterScale, 0]
		if let entity = attachments.entity(for: "detail") {
			if entity.parent !== selectionContainer {
				entity.components.set(BillboardComponent())
				selectionContainer.addChild(entity)
			}
			entity.position = card
			entity.scale = SIMD3(repeating: counterScale)
			detailEntity = entity
		}
		let direction = card - top
		let length = simd_length(direction)
		tether.position = top + direction / 2
		tether.scale = [counterScale, max(length - 0.05 * counterScale, 0.001), counterScale]
		tether.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(direction))
		tether.isEnabled = true
	}

	// MARK: Links and routes

	func apply(links: [SpatialLinkSnapshot], preset: ModemPresets) {
		guard placement != nil else { return }
		var wanted = Set<String>()
		for link in links {
			guard let a = pins[link.a]?.holder.position, let b = pins[link.b]?.holder.position else { continue }
			let lift = SIMD3<Float>(0, Self.pinTop * counterScale, 0)
			let start = a + lift, end = b + lift
			for (suffix, from, to, snr) in [(">", start, end, link.snrAtoB), ("<", end, start, link.snrBtoA)] {
				guard let snr else { continue }
				let key = link.id + suffix
				wanted.insert(key)
				let entity = linkEntities[key] ?? {
					let e = ModelEntity(mesh: Self.linkMesh, materials: [UnlitMaterial(color: .white)])
					linksContainer.addChild(e)
					linkEntities[key] = e
					return e
				}()
				// Each direction gets its own half of the line, colored by the SNR heard at its end.
				Self.lay(entity, from: from, to: simd_mix(from, to, SIMD3(repeating: 0.5)))
				entity.model?.materials = [UnlitMaterial(color: UIColor(getSnrColor(snr: snr, preset: preset)))]
			}
		}
		for (key, entity) in linkEntities where !wanted.contains(key) {
			entity.removeFromParent()
			linkEntities[key] = nil
		}
	}

	static func lay(_ entity: ModelEntity, from: SIMD3<Float>, to: SIMD3<Float>) {
		let direction = to - from
		let length = simd_length(direction)
		entity.position = from + direction / 2
		entity.scale = [1, 1, max(length, 0.0005)]
		entity.orientation = length > 0 ? simd_quatf(from: [0, 0, 1], to: direction / length) : simd_quatf(angle: 0, axis: [0, 1, 0])
	}

	/// Draws the legs a flyover is about to follow; empty clears them.
	func showRoute(legs: [[SIMD3<Float>]], color: UIColor) {
		for entity in routeEntities { entity.removeFromParent() }
		routeEntities = []
		for leg in legs where leg.count >= 2 {
			for i in 0..<(leg.count - 1) {
				let entity = ModelEntity(mesh: Self.linkMesh, materials: [Self.transparentMaterial(color, opacity: 0.85)])
				entity.scale = [1.6, 1.6, 1]
				Self.lay(entity, from: leg[i], to: leg[i + 1])
				entity.scale.x = 1.6
				entity.scale.y = 1.6
				trafficContainer.addChild(entity)
				routeEntities.append(entity)
			}
		}
	}

	// MARK: User transform

	func setTransform(yaw: Float, scale: Float, pan: SIMD2<Float>, animated: Bool = false) {
		var transform = Transform()
		transform.rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
		transform.scale = SIMD3(repeating: scale)
		transform.translation = [pan.x, 0, pan.y]
		if animated {
			model.move(to: transform, relativeTo: root, duration: 0.35, timingFunction: .easeInOut)
		} else {
			model.transform = transform
		}
		let counter = 1 / scale
		guard counter != counterScale else { return }
		counterScale = counter
		for pin in pins.values { pin.holder.scale = SIMD3(repeating: counter) }
		handle.scale = SIMD3(repeating: counter)
	}
}
#endif
