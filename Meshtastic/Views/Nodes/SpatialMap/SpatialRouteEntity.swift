//
//  SpatialRouteEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import RealityKit
import SwiftUI

/// The trace route picked in the flyover menu, drawn like the 2D map and the share image: forward
/// legs solid orange (short dashes where the SNR is unknown), return legs dashed blue, each with a
/// dark edge; shared legs side by side; chevrons for the direction; rings on the origin and target;
/// and attachment slots for the hop badges and SNR pills. Built once per route and rebuilt only
/// when the pins move or the scale changes, so the only per-frame work is the chevrons' drift.
@MainActor
final class SpatialRouteDrawing {
	/// Where the route's attachments go: the hop badges and SNR pills are SwiftUI views the
	/// RealityView makes, placed under these anchors.
	static func badgeAttachmentID(_ id: String) -> String { "route-badge-\(id)" }
	static func pillAttachmentID(_ id: String) -> String { "route-pill-\(id)" }

	/// A node's foot on the ground and the top of its pin, under the terrain anchor, and whether it
	/// is on the part of the map shown.
	struct Anchor: Equatable {
		let foot: SIMD3<Float>
		let top: SIMD3<Float>
		let onDisk: Bool
	}

	private struct Key: Equatable {
		let routeID: Int64
		let anchors: [Int64: Anchor]
		let counterScale: Float
		let clip: SpatialRouteClip
	}

	/// A drawn leg, after any side offset, for placing its chevrons.
	private struct Leg {
		let start: SIMD3<Float>
		let end: SIMD3<Float>
		let length: Float
		let isBack: Bool
	}

	private struct Chevron {
		let entity: ModelEntity
		let start: SIMD3<Float>
		let direction: SIMD3<Float>
		let margin: Float
		let usable: Float
		let base: Float
	}

	let root = Entity()
	private let lines = ModelEntity()
	private let casing = ModelEntity()
	private let originRing: ModelEntity
	private let targetRing: ModelEntity
	private var chevrons: [Chevron] = []
	private var chevronPool: [ModelEntity] = []
	private var badgeAnchors: [String: Entity] = [:]
	private var pillAnchors: [String: Entity] = [:]
	private var key: Key?
	private var phase: Float = 0
	private var counterScale: Float = 1

	private static let traits = UITraitCollection(userInterfaceStyle: .dark)
	static let forwardColor = UIColor(TraceRouteColors.forward).resolvedColor(with: traits)
	static let backColor = UIColor(TraceRouteColors.back).resolvedColor(with: traits)
	private static let forwardMaterial = trueColor(forwardColor)
	private static let backMaterial = trueColor(backColor)
	/// Chevrons a shade lighter than their line so they read against it.
	private static let forwardChevronMaterial = trueColor(forwardColor.lighter(componentDelta: 0.22))
	private static let backChevronMaterial = trueColor(backColor.lighter(componentDelta: 0.12))

	/// Unlit and left out of the tone mapping, which otherwise darkens and washes out the route
	/// colors, so the lines match the hop timeline and the legend.
	private static func trueColor(_ color: UIColor) -> UnlitMaterial {
		var material = UnlitMaterial(applyPostProcessToneMap: false)
		material.color = .init(tint: color)
		return material
	}
	/// The dark edge draws only its inside faces, so it shows as an outline around the line.
	private static let casingMaterial: UnlitMaterial = {
		var material = UnlitMaterial(color: UIColor(white: 0.06, alpha: 1))
		material.faceCulling = .front
		return material
	}()
	private static let chevronMesh = MeshResource.generateCone(height: 0.009, radius: 0.0036)
	/// Just outside the activity halo under each pin.
	private static let ringRadius: Float = 0.0165
	/// Badges sit to the right of the pin's head on the way out, and lower down on the way back,
	/// like the 2D map, so a node on both paths shows both numbers. Far enough right to clear the
	/// node's label, which is in front of them when the table is seen from above.
	private static let forwardBadgeOffset: SIMD3<Float> = [0.021, -0.002, 0]
	private static let backBadgeOffset: SIMD3<Float> = [0.021, -0.018, 0]
	/// SNR pills float this far above their line so a line running toward the viewer doesn't
	/// cross the text.
	private static let pillLift: Float = 0.009

	init() {
		root.name = "route"
		root.addChild(casing)
		root.addChild(lines)
		let ringMesh = SpatialTowerParts.ringMesh ?? .generateCylinder(height: 0.0005, radius: 1)
		originRing = ModelEntity(mesh: ringMesh, materials: [Self.trueColor(UIColor(TraceRouteShareStyle.originRing))])
		targetRing = ModelEntity(mesh: ringMesh, materials: [Self.trueColor(UIColor(TraceRouteShareStyle.destinationRing))])
		root.addChild(originRing)
		root.addChild(targetRing)
		root.isEnabled = false
	}

	/// Draws `route` between `anchors` (by node number), cut at the rim by `clip`, or clears it
	/// when `route` is nil. Does nothing when neither the route, the anchors, the scale nor the
	/// zoom changed.
	func update(route: SpatialRouteSnapshot?, anchors: [Int64: Anchor], counterScale: Float, clip: SpatialRouteClip) {
		guard let route else {
			if key != nil { clear() }
			return
		}
		let next = Key(routeID: route.id, anchors: anchors, counterScale: counterScale, clip: clip)
		guard next != key else { return }
		key = next
		self.counterScale = counterScale
		build(route.layout, anchors: anchors, scale: counterScale, clip: clip)
		root.isEnabled = true
	}

	private func clear() {
		key = nil
		root.isEnabled = false
		lines.model = nil
		casing.model = nil
		for chevron in chevrons { chevron.entity.removeFromParent() }
		for entity in chevronPool { entity.removeFromParent() }
		chevrons = []
		chevronPool = []
		phase = 0
		for anchor in badgeAnchors.values { anchor.removeFromParent() }
		for anchor in pillAnchors.values { anchor.removeFromParent() }
		badgeAnchors = [:]
		pillAnchors = [:]
	}

	// MARK: Building

	private func build(_ layout: SpatialRouteLayout, anchors: [Int64: Anchor], scale: Float, clip: SpatialRouteClip) {
		typealias Geometry = SpatialRouteGeometry
		var forward = SpatialMeshData(), back = SpatialMeshData(), edge = SpatialMeshData()
		var drawn: [Leg] = []
		var pills: [(id: String, points: [SIMD3<Float>])] = []
		for segment in layout.segments {
			guard let from = anchors[segment.fromNum]?.top, let to = anchors[segment.toNum]?.top else { continue }
			// A leg to a node past the rim stops at the rim.
			guard let range = clip.range(from: from, to: to) else { continue }
			let offset = segment.sharesLeg ? Geometry.rightSide(from: from, to: to) * Geometry.sharedOffset * scale : .zero
			let a = simd_mix(from, to, SIMD3(repeating: range.x)) + offset
			let b = simd_mix(from, to, SIMD3(repeating: range.y)) + offset
			let length = simd_distance(a, b)
			guard length > 1e-6 else { continue }
			let width = (segment.isBack ? Geometry.backWidth : Geometry.forwardWidth) * scale
			let edgeWidth = width + Geometry.casingExtra * scale
			if segment.isDashed {
				let short = !segment.isBack
				let dash = (short ? Geometry.shortDashLength : Geometry.dashLength) * scale
				let gap = (short ? Geometry.shortDashGap : Geometry.dashGap) * scale
				let dashes = Geometry.dashes(length: length, dash: dash, gap: gap)
				if segment.isBack {
					back.addDashes(from: a, to: b, dashes: dashes, width: width)
				} else {
					forward.addDashes(from: a, to: b, dashes: dashes, width: width)
				}
				edge.addDashes(from: a, to: b, dashes: dashes, width: edgeWidth)
			} else {
				forward.addCappedBar(from: a, to: b, width: width)
				edge.addCappedBar(from: a, to: b, width: edgeWidth)
			}
			drawn.append(Leg(start: a, end: b, length: length, isBack: segment.isBack))
			// The pill sits on the line, a little above it; legs too short in the room go without.
			if segment.snr != nil, length / scale >= Geometry.pillMinLegLength {
				let lift = SIMD3<Float>(0, Self.pillLift * scale, 0)
				pills.append((segment.id, Geometry.pillFractions(preferred: segment.pillFraction).map { simd_mix(a, b, SIMD3(repeating: $0)) + lift }))
			}
		}
		lines.model = Self.model(meshes: [(forward, Self.forwardMaterial), (back, Self.backMaterial)])
		casing.model = Self.model(meshes: [(edge, Self.casingMaterial)])
		buildChevrons(drawn, scale: scale)
		placeRings(layout, anchors: anchors, scale: scale)
		placeBadges(layout.badges, anchors: anchors, scale: scale)
		placePills(pills, nodes: anchors.values.filter(\.onDisk).map(\.top), scale: scale)
	}

	/// One model with a part per material, so a whole route is two draw entities.
	private static func model(meshes: [(SpatialMeshData, UnlitMaterial)]) -> ModelComponent? {
		var descriptors: [MeshDescriptor] = []
		var materials: [UnlitMaterial] = []
		for (data, material) in meshes where !data.indices.isEmpty {
			var descriptor = MeshDescriptor()
			descriptor.positions = MeshBuffers.Positions(data.positions)
			descriptor.normals = MeshBuffers.Normals(data.normals)
			descriptor.primitives = .triangles(data.indices)
			descriptor.materials = .allFaces(UInt32(materials.count))
			descriptors.append(descriptor)
			materials.append(material)
		}
		guard !descriptors.isEmpty, let mesh = try? MeshResource.generate(from: descriptors) else { return nil }
		return ModelComponent(mesh: mesh, materials: materials)
	}

	/// Reuses the chevron entities already made, so a pinch, which rebuilds the route every frame,
	/// doesn't make new ones each time. Spare ones are hidden.
	private func buildChevrons(_ legs: [Leg], scale: Float) {
		var spare = chevrons.map(\.entity) + chevronPool
		chevrons = []
		let spacing = SpatialRouteGeometry.chevronSpacing * scale
		let margin = SpatialRouteGeometry.chevronMargin * scale
		for leg in legs {
			let a = leg.start
			let direction = (leg.end - a) / leg.length
			let usable = max(leg.length - 2 * margin, 0)
			let orientation = simd_quatf(from: [0, 1, 0], to: direction)
			let material = leg.isBack ? Self.backChevronMaterial : Self.forwardChevronMaterial
			for distance in SpatialRouteGeometry.marks(length: leg.length, spacing: spacing, margin: margin) {
				let entity = spare.popLast() ?? {
					let made = ModelEntity(mesh: Self.chevronMesh, materials: [material])
					root.addChild(made)
					return made
				}()
				entity.model?.materials = [material]
				entity.isEnabled = true
				entity.orientation = orientation
				entity.scale = SIMD3(repeating: scale)
				entity.position = a + direction * distance
				chevrons.append(Chevron(entity: entity, start: a, direction: direction, margin: usable > 0 ? margin : distance, usable: usable, base: distance))
			}
		}
		for entity in spare { entity.isEnabled = false }
		chevronPool = spare
	}

	private func placeRings(_ layout: SpatialRouteLayout, anchors: [Int64: Anchor], scale: Float) {
		for (ring, num) in [(originRing, layout.originNum), (targetRing, layout.targetNum)] {
			guard let num, let anchor = anchors[num], anchor.onDisk else {
				ring.isEnabled = false
				continue
			}
			let radius = Self.ringRadius * scale
			ring.position = anchor.foot + [0, 0.0011 * scale, 0]
			ring.scale = [radius, scale, radius]
			ring.isEnabled = true
		}
	}

	private func placeBadges(_ badges: [SpatialRouteLayout.Badge], anchors: [Int64: Anchor], scale: Float) {
		var wanted = Set<String>()
		for badge in badges {
			guard let node = anchors[badge.num], node.onDisk else { continue }
			let top = node.top
			let id = Self.badgeAttachmentID(badge.id)
			wanted.insert(id)
			let anchor = badgeAnchors[id] ?? Self.makeAnchor(in: root)
			badgeAnchors[id] = anchor
			anchor.position = top
			anchor.scale = SIMD3(repeating: scale)
			anchor.children.first?.position = badge.isBack ? Self.backBadgeOffset : Self.forwardBadgeOffset
		}
		for (id, anchor) in badgeAnchors where !wanted.contains(id) {
			anchor.removeFromParent()
			badgeAnchors[id] = nil
		}
	}

	/// Each pill takes the first spot along its leg that keeps clear of the nodes on the route and
	/// of the pills already placed, measured in the room; with none, it is left out.
	private func placePills(_ pills: [(id: String, points: [SIMD3<Float>])], nodes: [SIMD3<Float>], scale: Float) {
		let choices = SpatialRouteGeometry.choose(
			pills.map { $0.points.map { $0 / scale } }, minDistance: SpatialRouteGeometry.pillMinSeparation,
			obstacles: nodes.map { $0 / scale }, clearance: SpatialRouteGeometry.pillNodeClearance
		)
		var wanted = Set<String>()
		for (pill, choice) in zip(pills, choices) {
			guard let choice else { continue }
			let id = Self.pillAttachmentID(pill.id)
			wanted.insert(id)
			let anchor = pillAnchors[id] ?? Self.makeAnchor(in: root)
			pillAnchors[id] = anchor
			anchor.position = pill.points[choice]
			anchor.scale = SIMD3(repeating: scale)
		}
		for (id, anchor) in pillAnchors where !wanted.contains(id) {
			anchor.removeFromParent()
			pillAnchors[id] = nil
		}
	}

	/// A billboarded holder whose one child is where the attachment goes, so an offset in the
	/// child stays to the viewer's right however the table is turned.
	static func makeAnchor(in parent: Entity) -> Entity {
		let anchor = Entity()
		anchor.components.set(BillboardComponent())
		anchor.addChild(Entity())
		parent.addChild(anchor)
		return anchor
	}

	// MARK: Attachments

	/// Puts each badge and pill view the RealityView made under its anchor. Views for badges or
	/// pills not shown at this zoom stay unparented.
	func place(attachments: RealityViewAttachments, ids: [String]) {
		for id in ids {
			guard let entity = attachments.entity(for: id) else { continue }
			let slot = badgeAnchors[id]?.children.first ?? pillAnchors[id]?.children.first
			guard let slot else {
				if entity.parent != nil { entity.removeFromParent() }
				continue
			}
			if entity.parent !== slot { slot.addChild(entity) }
		}
	}

	// MARK: Per frame

	/// Moves the chevrons slowly along their legs, shrinking them near the ends so one coming
	/// round to the start grows in instead of popping. Still with Reduce Motion on.
	func step(deltaTime: Double) {
		guard !chevrons.isEmpty, !UIAccessibility.isReduceMotionEnabled else { return }
		phase += SpatialRouteGeometry.chevronDrift * counterScale * Float(deltaTime)
		let fade = SpatialRouteGeometry.chevronMargin * counterScale
		for chevron in chevrons where chevron.usable > 0 {
			var along = (chevron.base - chevron.margin + phase).truncatingRemainder(dividingBy: chevron.usable)
			if along < 0 { along += chevron.usable }
			let toEnd = min(along, chevron.usable - along)
			let size = min(toEnd / fade, 1) * counterScale
			chevron.entity.position = chevron.start + chevron.direction * (chevron.margin + along)
			chevron.entity.scale = SIMD3(repeating: max(size, 0.0001))
		}
	}
}

/// A relay's number on the route: filled orange with a white number on the way out, a blue ring
/// on the way back, like the hop timeline.
struct SpatialRouteHopBadge: View {
	let number: Int
	let isBack: Bool

	var body: some View {
		Text(verbatim: "\(number)")
			.font(.system(size: 13, weight: .bold, design: .rounded))
			.monospacedDigit()
			// Black on the orange: white on it is too faint for digits this small.
			.foregroundStyle(isBack ? Color.white : Color.black)
			.frame(minWidth: 22, minHeight: 22)
			.background(Circle().fill(isBack ? Color.black.opacity(0.7) : TraceRouteColors.forward))
			.overlay(Circle().strokeBorder(isBack ? TraceRouteColors.back : Color.white, lineWidth: isBack ? 2.5 : 1.5))
			.environment(\.colorScheme, .dark)
			.accessibilityHidden(true)
	}
}

/// The SNR of one leg, as a small pill in the SNR color.
struct SpatialRouteSnrPill: View {
	let snr: Float
	let color: Color

	var body: some View {
		Text("\(snr.formatted(.number.precision(.fractionLength(1)))) dB")
			.font(.system(size: 11, weight: .bold))
			.monospacedDigit()
			.foregroundStyle(.black)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(Capsule().fill(color))
			.overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.75))
			.fixedSize()
			.accessibilityHidden(true)
	}
}
#endif
