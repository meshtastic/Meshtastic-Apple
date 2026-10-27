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

extension CollisionComponent {
	/// A hit shape for looking and pinching only. As plain collision shapes, the physics engine
	/// worked out contacts between every pin, the wheel and the terrain mesh each frame, which kept
	/// the main thread fully busy and made turning the map stutter. A trigger in its own group that
	/// ignores itself still takes taps and drags but gets no contacts.
	static func inputTarget(_ shapes: [ShapeResource]) -> CollisionComponent {
		CollisionComponent(shapes: shapes, mode: .trigger, filter: CollisionFilter(group: spatialMapGroup, mask: .all.subtracting(spatialMapGroup)))
	}

	private static let spatialMapGroup = CollisionGroup(rawValue: 1 << 20)
}

/// Owns the entities in the volume and diffs the model's snapshots into them, so the RealityView
/// update closure stays a dispatcher. `root` sits on the middle of the volume floor; `model`
/// carries the user's rotation and the scale that makes the disk fill the volume's footprint;
/// `terrainAnchor` carries the preview of a zoom whose terrain is still building.
@MainActor
final class SpatialSceneController {
	nonisolated static let pinRadius: Float = 0.006
	nonisolated static let stemHeight: Float = 0.03
	nonisolated static let pinTop: Float = stemHeight + pinRadius * 2
	static let flyHeight: Float = pinTop + 0.03
	/// Infrastructure nodes stand as a lattice tower, as tall as their role, on a colored base.
	static let towerBaseRadius: Float = 0.0085
	nonisolated static let towerBaseHeight: Float = 0.003

	let root = Entity()
	let model = Entity()
	let terrainAnchor = Entity()
	/// Holds the coverage overlay, in model units like the terrain, so it is not counter-scaled.
	let coverageContainer = Entity()
	/// Holds the weather radar overlay, under the coverage.
	let weatherRadarContainer = Entity()
	let nodesContainer = Entity()
	let selectionContainer = Entity()
	let trafficContainer = Entity()
	let route = SpatialRouteDrawing()
	let links = SpatialLinkDrawing()
	let wheel = SpatialWheelEntity()
	var updateSubscription: EventSubscription?

	@MainActor
	private struct Pin {
		let holder: Entity
		/// Takes taps and shows the hover highlight: a pin's head, or a tower with its base.
		let target: Entity
		/// The part in the node's color: a pin's head, a tower's base.
		let colored: ModelEntity
		/// The tower standing on the base, nil for a pin.
		let tower: Tower?
		let halo: ModelEntity
		var baseGlow: Float
		/// Distance to the nearest other pin in model units.
		var gap: Float = .infinity
		var hitShape: HitShapeKey?
		/// On the disk, so drawn. Pins outside the circle shown are hidden.
		var shown = true

		var isTower: Bool { tower != nil }

		/// Height of the top above the ground before counter-scaling, where labels and links attach.
		var top: Float {
			if let tower { return SpatialSceneController.towerBaseHeight + tower.height }
			return SpatialSceneController.pinTop
		}
	}

	@MainActor
	private struct Tower {
		let height: Float
		let beacon: Entity
	}

	/// An online tower's light, with the brightness step it was last set to.
	@MainActor
	private struct Beacon {
		let entity: Entity
		let offset: Double
		var level = -1
	}

	/// A pin's hit radius in half millimeters, the head's size in percent and, for a tower, its
	/// height in tenths of a millimeter (0 for a pin).
	private struct HitShapeKey: Hashable {
		let radius: Int
		let size: Int
		let towerHeight: Int
	}

	private static let pinMesh = MeshResource.generateSphere(radius: pinRadius)
	private static let stemMesh = MeshResource.generateCylinder(height: stemHeight, radius: 0.0008)
	private static let haloMesh = MeshResource.generateCylinder(height: 0.0008, radius: 0.014)
	private static let ringMesh = MeshResource.generateCylinder(height: 0.0012, radius: 0.02)
	private static let tetherMesh = MeshResource.generateCylinder(height: 1, radius: 0.0006)
	/// A pin's hit target is a ball around the head, up to 2.5 cm across, and a thinner capsule down
	/// the stem, set on the head so the hover highlight shows on the part people look at. Both
	/// narrow where pins crowd together so neighbors don't take each other's taps.
	private static let maxHitRadius: Float = 0.0125
	private static let minHitRadius: Float = pinRadius * 1.2

	private var placeholder: ModelEntity
	private var terrainEntity: ModelEntity?
	private var coverageEntity: ModelEntity?
	private var coverageOpacity: Float?
	private var weatherRadarEntity: ModelEntity?
	private var pins: [Int64: Pin] = [:]
	private var hitShapes: [HitShapeKey: [ShapeResource]] = [:]
	private var applied: [Int64: SpatialNodeSnapshot] = [:]
	private var appliedPlacementRevision = -1
	private(set) var placement: SpatialPlacement?
	private var labelEntities: [Int64: Entity] = [:]
	private let ring: ModelEntity
	private let tether: ModelEntity
	private var detailEntity: Entity?
	private var appliedSelection: Int64?
	/// The lights of online towers, kept so each frame touches only them.
	private var beacons: [Beacon] = []
	private var beaconsStale = false
	private var beaconClock: Double = 0
	/// The table's turn, eased and coasting frame by frame. Kept here rather than in view state so
	/// a drag never makes SwiftUI evaluate the view again.
	private var wheelMotion = SpatialWheelMotion()
	/// The turn and table point a drag started from.
	private var wheelDragStart: (yaw: Float, point: SIMD2<Float>)?
	/// Model units per meter for everything under the terrain anchor, so pins, labels and the card
	/// keep the same size in the room whatever the table's size and the zoom preview.
	private(set) var counterScale: Float = 1
	/// The volume's bounds in scene space, once known.
	private var volume: BoundingBox?
	private(set) var currentFit: SpatialVolumeFit?
	/// The built terrain scaled and shifted toward a zoom that is still building.
	private var preview = SpatialZoom.Preview.identity
	private var previewTarget: SpatialCircle?

	init() {
		// A flat disk of radius 0.5, scaled to the map once there is one.
		placeholder = ModelEntity(mesh: .generateCylinder(height: 0.001, radius: 0.5), materials: [Self.transparentMaterial(.systemGray, opacity: 0.25)])
		placeholder.name = "placeholder"
		ring = ModelEntity(mesh: Self.ringMesh, materials: [UnlitMaterial(color: .white)])
		tether = ModelEntity(mesh: Self.tetherMesh, materials: [Self.transparentMaterial(.white, opacity: 0.7)])
		ring.isEnabled = false
		tether.isEnabled = false
		NodePinComponent.registerComponent()
		root.addChild(model)
		model.addChild(terrainAnchor)
		model.addChild(wheel.root)
		terrainAnchor.addChild(placeholder)
		terrainAnchor.addChild(weatherRadarContainer)
		terrainAnchor.addChild(coverageContainer)
		terrainAnchor.addChild(nodesContainer)
		terrainAnchor.addChild(links.root)
		terrainAnchor.addChild(route.root)
		terrainAnchor.addChild(selectionContainer)
		terrainAnchor.addChild(trafficContainer)
		selectionContainer.addChild(ring)
		selectionContainer.addChild(tether)
		root.addChild(ownLight)
	}

	static func transparentMaterial(_ color: UIColor, opacity: Float) -> UnlitMaterial {
		var material = UnlitMaterial(color: color)
		material.blending = .transparent(opacity: .init(floatLiteral: opacity))
		return material
	}

	static func nodeColor(_ nodeNum: Int64) -> UIColor {
		UIColor(hex: UInt32(truncatingIfNeeded: nodeNum))
	}

	/// Sets the map on the middle of the volume floor, a little above it, and scales it so the disk
	/// fills the footprint. Called again whenever the volume is resized.
	func fit(volume bounds: BoundingBox) {
		guard bounds != volume else { return }
		volume = bounds
		// The RealityView's origin is the middle of the volume. The converted frame's z range doesn't
		// start there (its center sits half a depth toward the viewer), so only its size is used:
		// placing the disk at its center put the front half past the volume's front wall.
		root.position = [0, -bounds.extents.y / 2 + 0.03, 0]
		applyFit()
	}

	private func applyFit() {
		guard let volume else { return }
		let fit = SpatialVolumeFit(volumeWidth: volume.extents.x, volumeDepth: volume.extents.z, modelDiskRadius: placement?.diskRadius ?? 0.5)
		currentFit = fit
		model.scale = SIMD3(repeating: fit.scale)
		updateWheel(fit)
		updatePreview()
	}

	private func updateCounterScale() {
		guard let fit = currentFit else { return }
		let counter = 1 / (fit.scale * preview.scale)
		guard counter != counterScale else { return }
		counterScale = counter
		for pin in pins.values { pin.holder.scale = SIMD3(repeating: counter) }
		updateHitShapes()
		if let selection = appliedSelection, let pin = pins[selection], pin.shown {
			placeSelection(at: pin.holder.position, top: pin.top)
		}
	}

	/// The bezel hugs the rim and stands just above its highest point; it is built in meters, so
	/// it is counter-scaled against the model.
	private func updateWheel(_ fit: SpatialVolumeFit) {
		let skirtDepth = SpatialTerrainGeometry.defaultSkirtDepth
		let rimTop = placement?.geometry?.rimTop ?? 0
		let top = min(rimTop * fit.scale + SpatialWheelLayout.bezelLift, SpatialWheelLayout.maximumTop)
		wheel.root.scale = SIMD3(repeating: 1 / fit.scale)
		wheel.update(diskRadius: fit.diskRadius, bottom: -skirtDepth * fit.scale, top: top)
		// The wheel makes its rim, spokes and knobs here, once it knows its size.
		applyLight(to: wheel.root)
	}

	// MARK: Light

	/// The map's own light for the terrain, wheel and towers. Left to the system, they take the
	/// light of whatever is around: a dim room, or in the cinema the dusk tent, leaves the map in
	/// the shade.
	private let ownLight = SpatialMapLight.make()

	// MARK: Placement and terrain

	func apply(placement: SpatialPlacement?) {
		guard let placement, placement.revision != self.placement?.revision else { return }
		self.placement = placement
		let radius = placement.diskRadius
		placeholder.scale = [2 * radius, 1, 2 * radius]
		applyFit()
	}

	func apply(terrainEntity entity: ModelEntity?, building: Bool) {
		if entity !== terrainEntity {
			terrainEntity?.removeFromParent()
			if let entity {
				terrainAnchor.addChild(entity)
				applyLight(to: entity)
			}
			terrainEntity = entity
		}
		// While a new circle builds, the old terrain stays up with the zoom previewed on it.
		terrainEntity?.isEnabled = terrainEntity != nil
		placeholder.isEnabled = terrainEntity == nil
	}

	/// Shows the circle the map is heading for on the terrain that is built: scaled about the new
	/// center and held under the bezel, with pins past the rim hidden. Identity once it is built.
	func apply(target: SpatialCircle?) {
		guard target != previewTarget else { return }
		previewTarget = target
		updatePreview()
	}

	private func updatePreview() {
		var next = SpatialZoom.Preview.identity
		// Only a zoom in is previewed by enlarging the built terrain. Zooming out would have to shrink
		// it, leaving a bare ring inside the bezel until the rebuild; the table keeps its size and
		// the wider area replaces it when it is built.
		if let placement, let fit = currentFit, let target = previewTarget, target != placement.circle,
		   target.radiusMeters > 0, target.radiusMeters < placement.circle.radiusMeters {
			let center = placement.transform.position(CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude), altitude: placement.transform.baseElevation)
			let maxRadius = (fit.diskRadius + SpatialWheelLayout.gap + SpatialWheelLayout.bezelWidth) / fit.scale
			next = SpatialZoom.Preview(
				offset: SIMD2(center.x, center.z),
				scale: Float(placement.circle.radiusMeters / target.radiusMeters),
				diskRadius: placement.diskRadius, maxRadius: maxRadius
			)
		}
		if next != preview {
			preview = next
			terrainAnchor.scale = SIMD3(repeating: next.scale)
			terrainAnchor.position = [next.translation.x, 0, next.translation.y]
		}
		updateCounterScale()
		updatePinVisibility()
	}

	/// Hides pins that would stand past the rim, with their labels, links and selection.
	private func updatePinVisibility() {
		guard let placement else { return }
		var changed = false
		for (num, pin) in pins {
			let p = preview.apply(x: pin.holder.position.x, z: pin.holder.position.z)
			let shown = SpatialZoom.isOnDisk(x: p.x, z: p.y, diskRadius: placement.diskRadius)
			guard shown != pin.shown else { continue }
			pin.holder.isEnabled = shown
			pins[num]?.shown = shown
			changed = true
		}
		if changed, let selection = appliedSelection {
			if let pin = pins[selection], pin.shown {
				placeSelection(at: pin.holder.position, top: pin.top)
			} else {
				hideSelection()
			}
		}
	}

	// MARK: Nodes

	func apply(nodes: [SpatialNodeSnapshot]) {
		guard let placement else { return }
		let replaceAll = placement.revision != appliedPlacementRevision
		appliedPlacementRevision = placement.revision
		let now = Date()
		var seen = Set<Int64>()
		var moved = false
		var restyled = false
		for node in nodes {
			seen.insert(node.id)
			let previous = applied[node.id]
			// A role change between pin and tower, or between tower heights, builds the node again.
			if let pin = pins[node.id], previous?.towerHeight != node.towerHeight {
				pin.holder.removeFromParent()
				pins[node.id] = nil
			}
			if var pin = pins[node.id] {
				if replaceAll || previous == nil || !Self.samePlace(previous!, node) {
					pin.holder.position = placement.position(node.coordinate)
					moved = true
				}
				if previous == nil || !Self.sameLook(previous!, node) {
					style(pin, for: node)
					restyled = true
				}
				pin.baseGlow = NodeActivityGlow.baseOpacity(NodeActivityGlow.tier(lastHeard: node.lastHeard, now: now))
				pins[node.id] = pin
			} else {
				var pin = makePin(node)
				pin.holder.position = placement.position(node.coordinate)
				pin.holder.scale = SIMD3(repeating: counterScale)
				pin.baseGlow = NodeActivityGlow.baseOpacity(NodeActivityGlow.tier(lastHeard: node.lastHeard, now: now))
				pins[node.id] = pin
				nodesContainer.addChild(pin.holder)
				moved = true
			}
			applied[node.id] = node
		}
		for (num, pin) in pins where !seen.contains(num) {
			pin.holder.removeFromParent()
			pins[num] = nil
			applied[num] = nil
			labelEntities[num] = nil
			moved = true
		}
		if moved || restyled { beaconsStale = true }
		if moved {
			measureGaps()
			updatePinVisibility()
		}
		if moved || restyled { updateHitShapes() }
	}

	private func measureGaps() {
		let entries = Array(pins)
		for (i, entry) in entries.enumerated() {
			var gap = Float.infinity
			for (j, other) in entries.enumerated() where j != i {
				gap = min(gap, simd_distance(entry.value.holder.position, other.value.holder.position))
			}
			pins[entry.key]?.gap = gap
		}
	}

	/// Gives each pin a hit target half as wide as the space to its nearest neighbor at the
	/// current zoom, between a little over the head and the full 2.5 cm.
	private func updateHitShapes() {
		for (num, pin) in pins {
			let size = pin.target.scale.x
			let radius = min(max(pin.gap / counterScale / 2, Self.minHitRadius * size), Self.maxHitRadius)
			let key = HitShapeKey(radius: Int((radius * 2000).rounded()), size: Int((size * 100).rounded()), towerHeight: Int(((pin.tower?.height ?? 0) * 10_000).rounded()))
			guard key != pin.hitShape else { continue }
			pin.target.components.set(CollisionComponent.inputTarget(shapes(for: key)))
			pins[num]?.hitShape = key
		}
	}

	private func shapes(for key: HitShapeKey) -> [ShapeResource] {
		if let cached = hitShapes[key] { return cached }
		if key.towerHeight > 0 { return towerShapes(for: key) }
		// In the head's space, which is scaled by its size around the head's center.
		let size = Float(key.size) / 100
		let radius = Float(key.radius) / 2000
		let head = ShapeResource.generateSphere(radius: radius / size)
		// The stem capsule runs from just above the ground up into the head.
		let stemRadius = max(radius * 0.5, 0.004)
		let bottom: Float = 0.004, top = Self.stemHeight + Self.pinRadius
		let stem = ShapeResource.generateCapsule(height: (top - bottom + 2 * stemRadius) / size, radius: stemRadius / size)
			.offsetBy(translation: [0, ((top + bottom) / 2 - top) / size, 0])
		let shapes = [head, stem]
		hitShapes[key] = shapes
		return shapes
	}

	private static func samePlace(_ a: SpatialNodeSnapshot, _ b: SpatialNodeSnapshot) -> Bool {
		a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude && a.altitude == b.altitude
	}

	private static func sameLook(_ a: SpatialNodeSnapshot, _ b: SpatialNodeSnapshot) -> Bool {
		a.isOnline == b.isOnline && a.isFavorite == b.isFavorite && a.isConnectedRadio == b.isConnectedRadio
	}

	/// Where a shown pin's top is, under the terrain anchor; nil for a hidden one.
	func pinPosition(_ nodeNum: Int64) -> SIMD3<Float>? {
		guard let pin = pins[nodeNum], pin.shown else { return nil }
		return pin.holder.position + [0, pin.top * counterScale, 0]
	}

	/// The pin whose stem stands nearest a point in scene space, when the point is about within its
	/// hit target. For a tap that lands on the ground just beside a pin.
	func nearestPin(toScenePoint point: SIMD3<Float>) -> Int64? {
		let local = nodesContainer.convert(position: point, from: nil)
		var best: (num: Int64, distance: Float)?
		for (num, pin) in pins where pin.shown {
			let base = pin.holder.position
			let y = min(max(local.y - base.y, 0), pin.top * counterScale)
			let distance = simd_distance(local, base + [0, y, 0])
			let reach = Float(pin.hitShape?.radius ?? 0) / 2000 * 1.2 * counterScale
			if distance <= reach, distance < (best?.distance ?? .infinity) { best = (num, distance) }
		}
		return best?.num
	}

	/// The middle of the light on a shown, online tower, under the terrain anchor; nil otherwise.
	func antennaPosition(_ nodeNum: Int64) -> SIMD3<Float>? {
		guard let pin = pins[nodeNum], let tower = pin.tower, pin.shown, tower.beacon.isEnabled else { return nil }
		let top = Self.towerBaseHeight + SpatialTower.beaconCenter(height: tower.height)
		return pin.holder.position + [0, top * counterScale, 0]
	}

	func baseGlow(_ nodeNum: Int64) -> Float {
		pins[nodeNum]?.baseGlow ?? 0
	}

	func setHalo(_ nodeNum: Int64, opacity: Float, scale: Float) {
		guard let pin = pins[nodeNum] else { return }
		pin.halo.components.set(OpacityComponent(opacity: opacity))
		pin.halo.scale = SIMD3(scale, 1, scale)
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
				// So a tap the label's button doesn't take still selects this node, not whatever is nearby.
				entity.components.set(NodePinComponent(nodeNum: num))
				pin.holder.addChild(entity)
			}
			entity.position = [0, pin.top + 0.018, 0]
			labelEntities[num] = entity
		}
	}

	// MARK: Selection

	func apply(selection: Int64?, attachments: RealityViewAttachments) {
		guard let selection, let pin = pins[selection] else {
			hideSelection()
			detailEntity?.removeFromParent()
			detailEntity = nil
			appliedSelection = nil
			return
		}
		appliedSelection = selection
		ring.model?.materials = [UnlitMaterial(color: Self.nodeColor(selection))]
		if let entity = attachments.entity(for: "detail") {
			if entity.parent !== selectionContainer {
				entity.components.set(BillboardComponent())
				selectionContainer.addChild(entity)
			}
			detailEntity = entity
		}
		if pin.shown {
			placeSelection(at: pin.holder.position, top: pin.top)
		} else {
			hideSelection()
		}
	}

	private func hideSelection() {
		ring.isEnabled = false
		tether.isEnabled = false
		detailEntity?.isEnabled = false
	}

	/// The ring at the pin's foot, the card above its head and the line between them.
	private func placeSelection(at base: SIMD3<Float>, top height: Float) {
		ring.position = base + [0, 0.0007, 0]
		ring.scale = SIMD3(repeating: counterScale)
		ring.isEnabled = true
		let top = base + [0, height * counterScale, 0]
		let card = top + [0, 0.11 * counterScale, 0]
		detailEntity?.position = card
		detailEntity?.scale = SIMD3(repeating: counterScale)
		detailEntity?.isEnabled = true
		let direction = card - top
		let length = simd_length(direction)
		tether.position = top + direction / 2
		tether.scale = [counterScale, max(length - 0.05 * counterScale, 0.001), counterScale]
		tether.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(direction))
		tether.isEnabled = true
	}
}

extension SpatialSceneController {
	// MARK: Pins and towers

	private func makePin(_ node: SpatialNodeSnapshot) -> Pin {
		if let tower = makeTower(node) { return tower }
		let color = Self.nodeColor(node.id)
		let holder = Entity()
		holder.name = "node-\(node.id)"
		let stem = ModelEntity(mesh: Self.stemMesh, materials: [Self.transparentMaterial(.white, opacity: 0.55)])
		stem.position = [0, Self.stemHeight / 2, 0]
		let pin = ModelEntity(mesh: Self.pinMesh, materials: [UnlitMaterial(color: color)])
		pin.position = [0, Self.stemHeight + Self.pinRadius, 0]
		pin.components.set(InputTargetComponent())
		pin.components.set(HoverEffectComponent())
		pin.components.set(NodePinComponent(nodeNum: node.id))
		let halo = ModelEntity(mesh: Self.haloMesh, materials: [UnlitMaterial(color: color)])
		halo.position = [0, 0.0006, 0]
		halo.components.set(OpacityComponent(opacity: 0))
		holder.addChild(stem)
		holder.addChild(pin)
		holder.addChild(halo)
		let result = Pin(holder: holder, target: pin, colored: pin, tower: nil, halo: halo, baseGlow: 0)
		style(result, for: node)
		return result
	}

	private func style(_ pin: Pin, for node: SpatialNodeSnapshot) {
		let color = Self.nodeColor(node.id)
		let size: Float = node.isConnectedRadio ? 1.5 : (node.isFavorite ? 1.2 : 1)
		if let tower = pin.tower {
			// A tower keeps its role's height; only its base widens.
			pin.colored.scale = [size, 1, size]
			tower.beacon.isEnabled = node.isOnline
		} else {
			pin.target.scale = SIMD3(repeating: size)
		}
		pin.colored.model?.materials = [UnlitMaterial(color: node.isOnline ? color : color.darker(componentDelta: 0.25))]
		pin.target.components.set(OpacityComponent(opacity: node.isOnline ? 1 : 0.6))
	}

	func forEachPin(_ body: (Int64) -> Void) {
		for num in pins.keys { body(num) }
	}

	static let towerBaseMesh = MeshResource.generateCylinder(height: towerBaseHeight, radius: towerBaseRadius)

	/// A tower's hit target is one capsule from its base to its top, in the tower's space, which
	/// stands on the ground.
	private func towerShapes(for key: HitShapeKey) -> [ShapeResource] {
		let size = Float(key.size) / 100
		let radius = Float(key.radius) / 2000 / size
		let top = Self.towerBaseHeight + Float(key.towerHeight) / 10_000 + 0.002
		let capsule = ShapeResource.generateCapsule(height: max(top, 2 * radius), radius: radius)
			.offsetBy(translation: [0, top / 2, 0])
		hitShapes[key] = [capsule]
		return [capsule]
	}

	/// The lattice tower standing on a disc in the node's color, with its light on top. Nil if the
	/// mesh can't be built, and the node falls back to a pin.
	private func makeTower(_ node: SpatialNodeSnapshot) -> Pin? {
		guard let height = node.towerHeight, let mesh = SpatialTowerParts.mesh(height: height) else { return nil }
		let color = Self.nodeColor(node.id)
		let holder = Entity()
		holder.name = "node-\(node.id)"
		let target = Entity()
		target.components.set(InputTargetComponent())
		target.components.set(HoverEffectComponent())
		target.components.set(NodePinComponent(nodeNum: node.id))
		let base = ModelEntity(mesh: Self.towerBaseMesh, materials: [UnlitMaterial(color: color)])
		base.position = [0, Self.towerBaseHeight / 2, 0]
		let lattice = ModelEntity(mesh: mesh, materials: [SpatialTowerParts.material])
		lattice.position = [0, Self.towerBaseHeight, 0]
		let beacon = SpatialTowerParts.makeBeacon(height: height)
		lattice.addChild(beacon)
		target.addChild(base)
		target.addChild(lattice)
		let halo = ModelEntity(mesh: Self.haloMesh, materials: [UnlitMaterial(color: color)])
		halo.position = [0, 0.0006, 0]
		halo.components.set(OpacityComponent(opacity: 0))
		holder.addChild(target)
		holder.addChild(halo)
		applyLight(to: holder)
		let result = Pin(holder: holder, target: target, colored: base, tower: Tower(height: height, beacon: beacon), halo: halo, baseGlow: 0)
		style(result, for: node)
		return result
	}

	/// Moves every online tower's light on by one frame, all on one clock. A light is only touched
	/// when its brightness moves a visible step.
	func stepBeacons(deltaTime: Double) {
		beaconClock += deltaTime
		if beaconsStale {
			beaconsStale = false
			beacons = pins.compactMap { num, pin in
				guard let tower = pin.tower, tower.beacon.isEnabled else { return nil }
				return Beacon(entity: tower.beacon, offset: SpatialTowerBeacon.offset(for: num))
			}
		}
		for i in beacons.indices {
			let level = Int((SpatialTowerBeacon.brightness(time: beaconClock, offset: beacons[i].offset) * 24).rounded())
			guard level != beacons[i].level else { continue }
			beacons[i].level = level
			beacons[i].entity.components.set(OpacityComponent(opacity: Float(level) / 24))
		}
	}
}

extension SpatialSceneController {
	// MARK: Routes

	/// Draws the picked trace route, or clears it when `route` is nil. Each node's end of a leg is
	/// the top of its pin; a node with no pin, such as one outside the area shown, uses where it
	/// was when traced. Legs running past the rim stop at it.
	func apply(route snapshot: SpatialRouteSnapshot?, attachments: RealityViewAttachments, attachmentIDs: [String]) {
		guard let snapshot, let placement else {
			route.update(route: nil, anchors: [:], counterScale: counterScale, clip: SpatialRouteClip(scale: 1, translation: .zero, radius: 0))
			return
		}
		let clip = SpatialRouteClip(scale: preview.scale, translation: preview.translation, radius: placement.diskRadius)
		var anchors: [Int64: SpatialRouteDrawing.Anchor] = [:]
		for (num, point) in snapshot.pointsByNum {
			if let pin = pins[num] {
				anchors[num] = .init(foot: pin.holder.position, top: pin.holder.position + [0, pin.top * counterScale, 0], onDisk: pin.shown)
			} else {
				let foot = placement.position(point.coordinate)
				anchors[num] = .init(foot: foot, top: foot + [0, Self.pinTop * counterScale, 0], onDisk: clip.isInside(foot))
			}
		}
		route.update(route: snapshot, anchors: anchors, counterScale: counterScale, clip: clip)
		route.place(attachments: attachments, ids: attachmentIDs)
	}

	// MARK: Links

	/// Draws the direct links between pins, cut at the rim, or clears them when `snapshots` is
	/// empty. Both ends need a pin; the links are built from the nodes on the map, so they have one.
	func apply(links snapshots: [SpatialLinkSnapshot], pills: [SpatialLinkPill], preset: ModemPresets, attachments: RealityViewAttachments, attachmentIDs: [String]) {
		links.preset = preset
		guard !snapshots.isEmpty, let placement else {
			links.update(links: [], pills: [], anchors: [:], counterScale: counterScale, clip: SpatialRouteClip(scale: 1, translation: .zero, radius: 0))
			return
		}
		let clip = SpatialRouteClip(scale: preview.scale, translation: preview.translation, radius: placement.diskRadius)
		var anchors: [Int64: SpatialRouteDrawing.Anchor] = [:]
		for link in snapshots {
			for num in [link.a, link.b] where anchors[num] == nil {
				guard let pin = pins[num] else { continue }
				anchors[num] = .init(foot: pin.holder.position, top: pin.holder.position + [0, pin.top * counterScale, 0], onDisk: pin.shown)
			}
		}
		links.update(links: snapshots, pills: pills, anchors: anchors, counterScale: counterScale, clip: clip)
		links.place(attachments: attachments, ids: attachmentIDs)
	}

	// MARK: User transform

	/// A point in scene space as x/z in meters from the middle of the table, in the table's
	/// unrotated frame, for following a drag around the center.
	func tablePoint(_ scenePoint: SIMD3<Float>) -> SIMD2<Float> {
		let local = root.convert(position: scenePoint, from: nil)
		return SIMD2(local.x, local.z)
	}

	/// The table's turn as shown.
	var currentYaw: Float { wheelMotion.shown }

	/// Follows a drag that started at `start` and is now at `current` (table points), at `time`
	/// seconds. The first call of a drag stops any coast and starts from where the table is.
	func dragWheel(start: SIMD2<Float>, current: SIMD2<Float>, time: Double) {
		let begin = wheelDragStart ?? (wheelMotion.grab(), start)
		wheelDragStart = begin
		let delta = SpatialWheelSpin.yawDelta(start: begin.point, current: current, diskRadius: currentFit?.diskRadius ?? 0.5)
		wheelMotion.drag(to: begin.yaw + delta, at: time)
	}

	/// Ends a drag. Let go at `time` with some speed and the table keeps spinning; a cancelled
	/// drag (no time) just settles where it is heading.
	func endWheelDrag(at time: Double?) {
		guard wheelDragStart != nil else { return }
		wheelDragStart = nil
		if let time { wheelMotion.release(at: time) }
	}

	/// Stops a coasting table where it is.
	func stopWheel() {
		wheelMotion.stop()
	}

	/// Swings the table back to north the short way round.
	func resetYaw() {
		wheelDragStart = nil
		wheelMotion.reset()
	}

	/// Moves the table's turn on by one frame, touching the table only when the turn changed.
	func stepWheel(deltaTime: Double) {
		guard wheelMotion.step(dt: deltaTime) else { return }
		model.orientation = simd_quatf(angle: wheelMotion.shown, axis: [0, 1, 0])
	}
}

// MARK: - Overlays

extension SpatialSceneController {
	/// Swaps in the coverage overlay. It is built for one terrain, so it only shows while that
	/// terrain (`revision`) is the one on the table; a new terrain hides it until its own is built.
	func apply(coverage entity: ModelEntity?, revision: Int?, opacity: Float) {
		if entity !== coverageEntity {
			coverageEntity?.removeFromParent()
			if let entity { coverageContainer.addChild(entity) }
			coverageEntity = entity
			coverageOpacity = opacity
		}
		if let coverageEntity, opacity != coverageOpacity {
			SpatialOverlayEntity.setOpacity(opacity, on: coverageEntity)
			coverageOpacity = opacity
		}
		coverageContainer.isEnabled = coverageEntity != nil && terrainEntity != nil && revision != nil && revision == placement?.revision
	}

	/// Swaps in the weather radar overlay. Like the coverage, it only shows on the terrain it was
	/// built for.
	func apply(weatherRadar entity: ModelEntity?, revision: Int?) {
		if entity !== weatherRadarEntity {
			weatherRadarEntity?.removeFromParent()
			if let entity { weatherRadarContainer.addChild(entity) }
			weatherRadarEntity = entity
		}
		weatherRadarContainer.isEnabled = weatherRadarEntity != nil && terrainEntity != nil && revision != nil && revision == placement?.revision
	}
}
extension SpatialSceneController {
	fileprivate func applyLight(to entity: Entity) {
		SpatialMapLight.apply(ownLight, to: entity)
	}
}

/// A plain daylit room's light for the map: bright overhead, softer around the walls, darker below.
@MainActor
enum SpatialMapLight {
	static func make() -> Entity {
		let light = Entity()
		light.name = "mapLight"
		if let environment {
			light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.5))
		}
		return light
	}

	/// Gives every lit part under `entity` the light.
	static func apply(_ light: Entity, to entity: Entity) {
		let receiver = ImageBasedLightReceiverComponent(imageBasedLight: light)
		var pending = [entity]
		while let next = pending.popLast() {
			if next.components.has(ModelComponent.self) {
				next.components.set(receiver)
			}
			pending += next.children
		}
	}

	private static let environment: EnvironmentResource? = {
		let width = 64, height = 32
		var pixels = [UInt8](repeating: 0, count: width * height)
		for row in 0..<height {
			let up = 1 - Double(row) / Double(height - 1)
			let level = 0.25 + 0.75 * pow(up, 1.2)
			for column in 0..<width {
				pixels[row * width + column] = UInt8(level * 255)
			}
		}
		guard let provider = CGDataProvider(data: Data(pixels) as CFData),
			let image = CGImage(
				width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
				space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
				provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
			) else { return nil }
		return try? EnvironmentResource(equirectangular: image)
	}()
}
#endif
