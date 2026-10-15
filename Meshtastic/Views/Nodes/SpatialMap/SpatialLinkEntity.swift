//
//  SpatialLinkEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
#if os(visionOS)
import RealityKit
import SwiftUI

/// The direct links between nodes on the spatial map, like the 2D map's: thin lines from pin top
/// to pin top in the signal quality color of the worse direction, dashed when only one direction
/// is known, fainter as they age, with slots for the SNR pills. All lines are one entity with a
/// part per color and fade step, built only when the links, the pins or the scale change. No
/// collision, so the lines never take a tap meant for a pin.
@MainActor
final class SpatialLinkDrawing {
	static func pillAttachmentID(_ id: String) -> String { "link-pill-\(id)" }

	/// Line sizes in meters in the room; the scene multiplies them by its counter-scale.
	static let width: Float = 0.0016
	static let dashLength: Float = 0.004
	static let dashGap: Float = 0.003
	/// Pills float this far above their line, like the trace route pills.
	static let pillLift: Float = 0.007
	/// Pills keep this far from each other and from the pins.
	static let pillMinSeparation: Float = 0.035
	static let pillNodeClearance: Float = 0.02
	/// A link shorter than this in the room has no pills.
	static let pillMinLinkLength: Float = 0.05

	private struct Key: Equatable {
		let links: [SpatialLinkSnapshot]
		let pills: [SpatialLinkPill]
		let anchors: [Int64: SpatialRouteDrawing.Anchor]
		let counterScale: Float
		let clip: SpatialRouteClip
		let preset: Int
	}

	/// A color and fade step the lines are grouped by, one mesh part each.
	private struct Style: Hashable {
		let quality: Int
		let opacity: Double
	}

	let root = Entity()
	/// Grades the SNR into the line colors; set before `update`.
	var preset: ModemPresets = .longFast
	private let lines = ModelEntity()
	private var pillAnchors: [String: Entity] = [:]
	private var key: Key?
	private var materials: [Style: UnlitMaterial] = [:]

	private static let traits = UITraitCollection(userInterfaceStyle: .dark)

	init() {
		root.name = "links"
		root.addChild(lines)
		root.isEnabled = false
	}

	/// Draws `links` between `anchors` (by node number), cut at the rim by `clip`, with `pills`
	/// placed where they fit. Does nothing when nothing changed. An empty `links` clears it.
	func update(links: [SpatialLinkSnapshot], pills: [SpatialLinkPill], anchors: [Int64: SpatialRouteDrawing.Anchor], counterScale: Float, clip: SpatialRouteClip) {
		guard !links.isEmpty else {
			if key != nil { clear() }
			return
		}
		let next = Key(links: links, pills: pills, anchors: anchors, counterScale: counterScale, clip: clip, preset: preset.rawValue)
		guard next != key else { return }
		key = next
		build(next)
		root.isEnabled = true
	}

	private func clear() {
		key = nil
		root.isEnabled = false
		lines.model = nil
		for anchor in pillAnchors.values { anchor.removeFromParent() }
		pillAnchors = [:]
	}

	private func build(_ key: Key) {
		let anchors = key.anchors, scale = key.counterScale, clip = key.clip
		var parts: [Style: SpatialMeshData] = [:]
		let width = Self.width * scale
		for link in key.links {
			guard let snr = link.worstSnr, let from = anchors[link.a]?.top, let to = anchors[link.b]?.top,
				  let range = clip.range(from: from, to: to)
			else { continue }
			let a = simd_mix(from, to, SIMD3(repeating: range.x))
			let b = simd_mix(from, to, SIMD3(repeating: range.y))
			let length = simd_distance(a, b)
			guard length > 1e-6 else { continue }
			let style = Style(quality: signalQuality(snrMargin: snr - preset.snrLimit()).rawValue, opacity: link.opacity)
			if link.isOneWay {
				let dashes = SpatialRouteGeometry.dashes(length: length, dash: Self.dashLength * scale, gap: Self.dashGap * scale)
				parts[style, default: SpatialMeshData()].addDashes(from: a, to: b, dashes: dashes, width: width)
			} else {
				parts[style, default: SpatialMeshData()].addCappedBar(from: a, to: b, width: width)
			}
		}
		lines.model = model(parts: parts)
		placePills(key.pills, anchors: anchors, scale: scale, clip: clip)
	}

	/// One model with a part per style. Brighter styles go last so they draw over faded ones.
	private func model(parts: [Style: SpatialMeshData]) -> ModelComponent? {
		var descriptors: [MeshDescriptor] = []
		var used: [UnlitMaterial] = []
		for (style, data) in parts.sorted(by: { ($0.key.opacity, $0.key.quality) < ($1.key.opacity, $1.key.quality) }) where !data.indices.isEmpty {
			var descriptor = MeshDescriptor()
			descriptor.positions = MeshBuffers.Positions(data.positions)
			descriptor.normals = MeshBuffers.Normals(data.normals)
			descriptor.primitives = .triangles(data.indices)
			descriptor.materials = .allFaces(UInt32(used.count))
			descriptors.append(descriptor)
			used.append(material(style))
		}
		guard !descriptors.isEmpty, let mesh = try? MeshResource.generate(from: descriptors) else { return nil }
		return ModelComponent(mesh: mesh, materials: used)
	}

	/// Unlit and left out of the tone mapping, like the trace route lines, so the colors match
	/// the signal meter.
	private func material(_ style: Style) -> UnlitMaterial {
		if let cached = materials[style] { return cached }
		let quality = LoRaSignalStrength(rawValue: style.quality) ?? .none
		var material = UnlitMaterial(applyPostProcessToneMap: false)
		material.color = .init(tint: UIColor(quality.color).resolvedColor(with: Self.traits))
		if style.opacity < 1 {
			material.blending = .transparent(opacity: .init(floatLiteral: Float(style.opacity)))
		}
		materials[style] = material
		return material
	}

	/// Each pill goes near the node that measured it, or a little further along when that spot
	/// would cover a pin or another pill; with no room, it is left out.
	private func placePills(_ pills: [SpatialLinkPill], anchors: [Int64: SpatialRouteDrawing.Anchor], scale: Float, clip: SpatialRouteClip) {
		var placeable: [(id: String, points: [SIMD3<Float>])] = []
		let lift = SIMD3<Float>(0, Self.pillLift * scale, 0)
		let fraction = SpatialLinkLayout.pillFraction
		for pill in pills {
			guard let at = anchors[pill.atNum], at.onDisk, let other = anchors[pill.otherNum],
				  simd_distance(at.top, other.top) / scale >= Self.pillMinLinkLength
			else { continue }
			let points = [fraction, fraction + 0.1, fraction - 0.1]
				.map { simd_mix(at.top, other.top, SIMD3(repeating: $0)) + lift }
				.filter { clip.isInside($0) }
			guard !points.isEmpty else { continue }
			placeable.append((pill.id, points))
		}
		let choices = SpatialRouteGeometry.choose(
			placeable.map { $0.points.map { $0 / scale } }, minDistance: Self.pillMinSeparation,
			obstacles: anchors.values.filter(\.onDisk).map { $0.top / scale }, clearance: Self.pillNodeClearance
		)
		var wanted = Set<String>()
		for (pill, choice) in zip(placeable, choices) {
			guard let choice else { continue }
			let id = Self.pillAttachmentID(pill.id)
			wanted.insert(id)
			let anchor = pillAnchors[id] ?? SpatialRouteDrawing.makeAnchor(in: root)
			pillAnchors[id] = anchor
			anchor.position = pill.points[choice]
			anchor.scale = SIMD3(repeating: scale)
		}
		for (id, anchor) in pillAnchors where !wanted.contains(id) {
			anchor.removeFromParent()
			pillAnchors[id] = nil
		}
	}

	/// Puts each pill view the RealityView made under its anchor. Views for pills that didn't fit
	/// stay unparented.
	func place(attachments: RealityViewAttachments, ids: [String]) {
		for id in ids {
			guard let entity = attachments.entity(for: id) else { continue }
			guard let slot = pillAnchors[id]?.children.first else {
				if entity.parent != nil { entity.removeFromParent() }
				continue
			}
			if entity.parent !== slot { slot.addChild(entity) }
		}
	}
}
#endif
