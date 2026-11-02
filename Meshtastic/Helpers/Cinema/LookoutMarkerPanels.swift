//
//  LookoutMarkerPanels.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
#if os(visionOS)
import Foundation
import RealityKit
import simd

/// Which marker's card is open out the lookout's windows, by the node the marker stands over, and
/// for a marker of several nodes, the one picked from its list.
struct LookoutCardSelection: Equatable {
	let lead: Int64
	var chosen: Int64?
}

/// The node markers out the lookout's windows, the stem under each, and the card beside the
/// selected one, on a bar that can be pinched to move it.
@MainActor final class LookoutMarkerPanels {
	private var placed: [String: Entity] = [:]
	private var stems: [String: ModelEntity] = [:]
	private var card: Entity?
	/// The bar under the card: pinch and drag it to move the card. It and the card keep facing
	/// the viewer.
	private let cardGrabber = LookoutMarkerPanels.makeCardGrabber()
	/// The marker the card was last hung beside. The card is placed once per marker, and then
	/// stays wherever the viewer moves it.
	private var cardPlacedBeside: Int64?
	/// Where the bar was put when the card was hung from the image's eye point because the head
	/// wasn't tracked yet. Nil once it was hung from the head.
	private var cardPlacedWithoutHead: SIMD3<Float>?
	/// The card was hung without the head; once the head is tracked it's hung again from there,
	/// unless the viewer has moved it.
	var cardAwaitingHead: Bool { cardPlacedWithoutHead != nil }
	/// A marker or the card hasn't laid out yet, so it couldn't be scaled; the frame update tries
	/// again.
	private(set) var unsized = false

	static let cardID = "lookoutCard"
	/// How much bigger the card is drawn than an attachment's points would make it, to read at
	/// reading distance.
	static let cardScale: Float = 1.6
	private static let grabberGap: Float = 0.012

	static func id(for spot: LookoutTerrain.MarkerSpot) -> String {
		"node-\(spot.lead.id)"
	}

	/// An attachment already hung, for the frame update, which has no attachments to ask.
	func entity(for id: String) -> Entity? {
		id == Self.cardID ? card : placed[id]
	}

	/// The marker entity for each spot, by its attachment, scaled to the same share of the view
	/// whatever its distance and facing the viewer, on a short stem toward its node; and the card,
	/// beside the selected marker as seen from `head` (the stage's eye point when nil).
	func place(_ spots: [LookoutTerrain.MarkerSpot], selected: Int64?, on stage: Entity, head: SIMD3<Float>?, entityFor: (String) -> Entity?) {
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
		if !placeCard(beside: spots.first { $0.lead.id == selected }, on: stage, head: head, entity: entityFor(Self.cardID)) {
			unsized = true
		}
		self.unsized = unsized
	}

	/// Hangs the card on its bar just to the right of its marker, as the viewer sees it, at reading
	/// distance and their own height. It hangs in the stage's room rather than on the stage, so
	/// turning the lookout doesn't carry it off. Once hung it stays put, so the viewer can move it,
	/// until another marker is picked. False when the card hasn't laid out yet.
	private func placeCard(beside spot: LookoutTerrain.MarkerSpot?, on stage: Entity, head: SIMD3<Float>?, entity: Entity?) -> Bool {
		if card !== entity {
			card?.removeFromParent()
			card = entity
			cardPlacedBeside = nil
			cardPlacedWithoutHead = nil
		}
		guard let spot, let entity else {
			entity?.removeFromParent()
			cardGrabber.isEnabled = false
			cardPlacedBeside = nil
			cardPlacedWithoutHead = nil
			return true
		}
		if let room = stage.parent, cardGrabber.parent !== room {
			room.addChild(cardGrabber)
		}
		if entity.parent !== cardGrabber {
			cardGrabber.addChild(entity)
		}
		entity.scale = SIMD3(repeating: Self.cardScale)
		let size = entity.visualBounds(relativeTo: entity).extents * Self.cardScale
		guard size.x > 0 else { return false }
		// The card sits just above the bar, however tall it is now.
		entity.position = [0, size.y / 2 + Self.grabberGap, 0]
		cardGrabber.isEnabled = true
		if cardPlacedBeside == spot.lead.id {
			// Hung once already. Only a card hung before the head was tracked, and not moved since,
			// is hung again, from the head.
			guard let placedAt = cardPlacedWithoutHead, head != nil else { return true }
			guard simd_distance(cardGrabber.position(relativeTo: nil), placedAt) < 0.001 else {
				cardPlacedWithoutHead = nil
				return true
			}
		}
		cardPlacedBeside = spot.lead.id
		let marker = stage.convert(position: LookoutTerrain.direction(azimuth: spot.azimuth, elevation: spot.center) * spot.depth, to: nil)
		let eye = head ?? stage.convert(position: .zero, to: nil)
		let center = LookoutCardPlacement.center(eye: eye, marker: marker, markerWidthDegrees: LookoutTerrain.markerWidthDegrees, cardHalfWidth: size.x / 2)
		cardGrabber.setPosition(center - [0, size.y / 2 + Self.grabberGap, 0], relativeTo: nil)
		cardPlacedWithoutHead = head == nil ? cardGrabber.position(relativeTo: nil) : nil
		return true
	}

	/// A bar like a window's, the cinema panel's twin.
	private static func makeCardGrabber() -> Entity {
		var material = UnlitMaterial(color: .white)
		material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
		let bar = ModelEntity(mesh: .generateBox(width: 0.08, height: 0.008, depth: 0.008, cornerRadius: 0.004), materials: [material])
		bar.name = "LookoutCardGrabber"
		ManipulationComponent.configureEntity(
			bar,
			hoverEffect: .highlight(.default),
			allowedInputTypes: .all,
			collisionShapes: [.generateBox(width: 0.14, height: 0.035, depth: 0.03)]
		)
		var manipulation = bar.components[ManipulationComponent.self] ?? ManipulationComponent()
		manipulation.releaseBehavior = .stay
		manipulation.dynamics.scalingBehavior = .none
		manipulation.dynamics.primaryRotationBehavior = .none
		manipulation.dynamics.secondaryRotationBehavior = .none
		bar.components.set(manipulation)
		bar.components.set(BillboardComponent())
		var accessibility = AccessibilityComponent()
		accessibility.isAccessibilityElement = true
		accessibility.label = LocalizedStringResource("Move the node card", comment: "Cinema: VoiceOver label for the bar under a node's card out the fire lookout's windows that moves it")
		bar.components.set(accessibility)
		bar.isEnabled = false
		return bar
	}
}
#endif
