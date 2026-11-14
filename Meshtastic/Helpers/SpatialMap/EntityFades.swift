//
//  EntityFades.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//
#if os(visionOS)
import RealityKit

/// Entities fading in or out, stepped each frame by the scene that holds them: the 3D map's terrain
/// and overlays, and the terrain out the cinema's windows. A class, so stepping it every frame
/// doesn't touch any view's state.
@MainActor
final class EntityFades {
	/// What happens to an entity once its fade is done.
	enum End {
		/// Stays, drawn normally again.
		case keep
		/// Stays, switched off.
		case disable
		/// Taken out of the scene.
		case remove
	}

	private struct Fade {
		let entity: Entity
		let target: Float
		let end: End
	}

	private var fades: [Fade] = []
	/// How long a fade from fully shown to gone takes, in seconds.
	private let duration: Float

	init(duration: Float = 0.4) {
		self.duration = duration
	}

	/// Fades `entity` from its opacity now to `target`, replacing any fade it had.
	func fade(_ entity: Entity, to target: Float, then end: End = .keep) {
		fades.removeAll { $0.entity === entity }
		fades.append(Fade(entity: entity, target: target, end: end))
	}

	/// Starts `entity` invisible and fades it in.
	func fadeIn(_ entity: Entity) {
		entity.components.set(OpacityComponent(opacity: 0))
		fade(entity, to: 1)
	}

	/// Moves each fade on by a frame.
	func step(deltaTime: Double) {
		guard !fades.isEmpty else { return }
		let step = Float(deltaTime) / duration
		fades.removeAll { fade in
			let current = fade.entity.components[OpacityComponent.self]?.opacity ?? 1
			let next = current < fade.target ? min(current + step, fade.target) : max(current - step, fade.target)
			guard next == fade.target else {
				fade.entity.components.set(OpacityComponent(opacity: next))
				return false
			}
			switch fade.end {
			case .keep:
				// Fully shown needs no opacity, which RealityKit draws with blending.
				if next >= 1 {
					fade.entity.components.remove(OpacityComponent.self)
				} else {
					fade.entity.components.set(OpacityComponent(opacity: next))
				}
			case .disable:
				fade.entity.isEnabled = false
				fade.entity.components.remove(OpacityComponent.self)
			case .remove:
				fade.entity.removeFromParent()
				fade.entity.components.remove(OpacityComponent.self)
			}
			return true
		}
	}
}
#endif
