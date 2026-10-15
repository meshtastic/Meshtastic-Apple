//
//  SpatialFlyoverComet.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
#if os(visionOS)
import RealityKit
import UIKit

/// The flyover marker: a bright head in the color of the leg being flown, a soft glow around it,
/// and a short tail of shrinking, fading beads that follow the route behind it. Everything is made
/// once and reused; nothing is allocated per frame.
@MainActor
final class SpatialFlyoverComet {
	static let tailCount = 6
	/// Seconds of flight between beads, so the tail stretches at the cruise and tucks in on landing.
	static let tailLag: TimeInterval = 0.07
	/// Longest gap between beads at counter scale 1, so the tail stays short when zoomed in.
	static let maxGap: Float = 0.0075
	static let headRadius: Float = 0.0052
	static let glowRadius: Float = 0.0095
	static let beadRadius: Float = 0.0045

	private struct Look {
		let head: UnlitMaterial
		let glow: UnlitMaterial
		let bead: UnlitMaterial
	}

	private static let headMesh = MeshResource.generateSphere(radius: headRadius)
	private static let glowMesh = MeshResource.generateSphere(radius: glowRadius)
	private static let beadMesh = MeshResource.generateSphere(radius: beadRadius)
	/// Indexed by the route leg: forward, then back.
	private static let looks = [look(SpatialRouteDrawing.forwardColor), look(SpatialRouteDrawing.backColor)]

	private static func look(_ color: UIColor) -> Look {
		Look(
			head: trueColor(color.lighter(componentDelta: 0.14)),
			glow: trueColor(color, opacity: 0.4),
			bead: trueColor(color)
		)
	}

	/// Unlit and left out of tone mapping, like the route lines, so the colors match them.
	private static func trueColor(_ color: UIColor, opacity: Float = 1) -> UnlitMaterial {
		var material = UnlitMaterial(applyPostProcessToneMap: false)
		material.color = .init(tint: color)
		if opacity < 1 { material.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
		return material
	}

	private let head: ModelEntity
	private let glow: ModelEntity
	private let beads: [ModelEntity]
	private var lookIndex = -1

	init(parent: Entity) {
		head = ModelEntity(mesh: Self.headMesh, materials: [Self.looks[0].head])
		glow = ModelEntity(mesh: Self.glowMesh, materials: [Self.looks[0].glow])
		head.addChild(glow)
		head.isEnabled = false
		parent.addChild(head)
		beads = (0..<Self.tailCount).map { index in
			let bead = ModelEntity(mesh: Self.beadMesh, materials: [Self.looks[0].bead])
			let fade = Float(index) / Float(Self.tailCount)
			bead.components.set(OpacityComponent(opacity: 0.85 - 0.7 * fade))
			bead.isEnabled = false
			parent.addChild(bead)
			return bead
		}
	}

	func hide() {
		head.isEnabled = false
		for bead in beads { bead.isEnabled = false }
	}

	/// Places the head `lift` above `position` and lays the tail back along the current leg.
	func update(_ flyover: SpatialFlyover, position: SIMD3<Float>, lift: Float, counterScale: Float, showTail: Bool) {
		guard flyover.legIndex < flyover.legs.count else { return hide() }
		let leg = flyover.legs[flyover.legIndex]
		let look = min(leg.source, Self.looks.count - 1)
		if look != lookIndex {
			lookIndex = look
			head.model?.materials = [Self.looks[look].head]
			glow.model?.materials = [Self.looks[look].glow]
			for bead in beads { bead.model?.materials = [Self.looks[look].bead] }
		}
		let up = SIMD3<Float>(0, lift, 0)
		head.position = position + up
		head.scale = SIMD3(repeating: counterScale)
		head.isEnabled = true

		guard showTail, let front = flyover.distanceBack(0) else {
			for bead in beads where bead.isEnabled { bead.isEnabled = false }
			return
		}
		let gap = Self.maxGap * counterScale
		let hidden = Self.headRadius * counterScale
		var previous = front
		for (index, bead) in beads.enumerated() {
			let step = Float(index + 1)
			let lagged = flyover.distanceBack(Self.tailLag * Double(step)) ?? 0
			let distance = max(lagged, front - step * gap)
			// Tucked under the head while it lands, or bunched at the start of the leg.
			guard front - distance > hidden, distance < previous - 0.0001 else {
				if bead.isEnabled { bead.isEnabled = false }
				continue
			}
			previous = distance
			bead.position = SpatialFlyover.point(on: leg, at: distance) + up
			bead.scale = SIMD3(repeating: counterScale * (1 - 0.55 * step / Float(Self.tailCount)))
			if !bead.isEnabled { bead.isEnabled = true }
		}
	}
}
#endif
