//
//  LookoutMarkerPanels.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
#if os(visionOS)
import RealityKit
import simd

/// Which marker's card is open out the lookout's windows, by the node the marker stands over, and
/// for a marker of several nodes, the one picked from its list.
struct LookoutCardSelection: Equatable {
	let lead: Int64
	var chosen: Int64?
}

/// The node markers out the lookout's windows, the stem under each, and the card beside the
/// selected one.
@MainActor final class LookoutMarkerPanels {
	private var placed: [String: Entity] = [:]
	private var stems: [String: ModelEntity] = [:]
	private var card: Entity?
	/// A marker or the card hasn't laid out yet, so it couldn't be scaled; the frame update tries
	/// again.
	private(set) var unsized = false

	static let cardID = "lookoutCard"
	/// How far from the eye the card hangs: inside the cab, near enough to read.
	static let cardDistance: Float = 1.4
	/// How much bigger the card is drawn than an attachment's points would make it, to read at
	/// that distance.
	static let cardScale: Float = 1.6

	static func id(for spot: LookoutTerrain.MarkerSpot) -> String {
		"node-\(spot.lead.id)"
	}

	/// An attachment already hung, for the frame update, which has no attachments to ask.
	func entity(for id: String) -> Entity? {
		id == Self.cardID ? card : placed[id]
	}

	/// The marker entity for each spot, by its attachment, scaled to the same share of the view
	/// whatever its distance and facing the viewer, on a short stem toward its node; and the card,
	/// beside the selected marker.
	func place(_ spots: [LookoutTerrain.MarkerSpot], selected: Int64?, on stage: Entity, entityFor: (String) -> Entity?) {
		var keep: Set<String> = []
		var unsized = false
		let widthPerDepth = Float(2 * tan(LookoutTerrain.markerWidthDegrees / 2 * .pi / 180))
		for spot in spots {
			let id = Self.id(for: spot)
			guard let entity = entityFor(id) else { continue }
			keep.insert(id)
			if entity.parent !== stage {
				stage.addChild(entity)
				entity.components.set(BillboardComponent())
				placed[id] = entity
			}
			let width = entity.visualBounds(relativeTo: entity).extents.x
			if width > 0 {
				entity.scale = SIMD3(repeating: widthPerDepth * spot.depth / width)
			} else {
				unsized = true
			}
			entity.position = LookoutTerrain.direction(azimuth: spot.azimuth, elevation: spot.center) * spot.depth
			let stem = stems[id] ?? {
				let made = ModelEntity(mesh: .generateBox(size: 1), materials: [UnlitMaterial(color: .white)])
				made.name = "stem-\(id)"
				stage.addChild(made)
				stems[id] = made
				return made
			}()
			let top = LookoutTerrain.direction(azimuth: spot.azimuth, elevation: spot.center - LookoutTerrain.markerWidthDegrees / 2) * spot.depth
			let foot = LookoutTerrain.direction(azimuth: spot.azimuth, elevation: spot.stemFoot) * spot.depth
			let run = foot - top
			let length = simd_length(run)
			stem.position = (foot + top) / 2
			stem.orientation = simd_quatf(from: SIMD3(0, -1, 0), to: run / length)
			stem.scale = SIMD3(0.0025 * spot.depth, length, 0.0025 * spot.depth)
		}
		for (id, entity) in placed where !keep.contains(id) {
			entity.removeFromParent()
			placed[id] = nil
			stems[id]?.removeFromParent()
			stems[id] = nil
		}
		if !placeCard(beside: spots.first { $0.lead.id == selected }, on: stage, entity: entityFor(Self.cardID)) {
			unsized = true
		}
		self.unsized = unsized
	}

	/// Hangs the card just to the right of its marker, inside the cab. False when it hasn't laid
	/// out yet.
	private func placeCard(beside spot: LookoutTerrain.MarkerSpot?, on stage: Entity, entity: Entity?) -> Bool {
		if card !== entity {
			card?.removeFromParent()
			card = entity
		}
		guard let spot, let entity else {
			entity?.removeFromParent()
			return true
		}
		if entity.parent !== stage {
			stage.addChild(entity)
			entity.components.set(BillboardComponent())
		}
		entity.scale = SIMD3(repeating: Self.cardScale)
		let halfWidth = entity.visualBounds(relativeTo: entity).extents.x * Self.cardScale / 2
		guard halfWidth > 0 else { return false }
		let halfDegrees = Double(atan(halfWidth / Self.cardDistance)) * 180 / .pi
		let azimuth = spot.azimuth + LookoutTerrain.markerWidthDegrees / 2 + halfDegrees + 1
		entity.position = LookoutTerrain.direction(azimuth: azimuth, elevation: max(spot.center, -2)) * Self.cardDistance
		return true
	}
}
#endif
