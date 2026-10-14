//
//  ShowcaseInspector.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import RealityKit
import SwiftUI

/// Marks the model being inspected, so only it takes the spin drag.
struct ShowcaseInspectedComponent: Component {}

/// Where a model rests on its stand, relative to the stand's holder. Recorded when it is stood
/// up, so it goes back to the right place however it was moved since.
struct ShowcaseHomeComponent: Component {
	let transform: Transform
}

/// Holds one model up in front of the viewer to look at: it glides off its stand to a spot past
/// the front table's edge, turns as the viewer drags, and glides back when let go. While it is
/// held up a drag spins it, so its hand grab is set aside until it is back on its stand.
@MainActor
final class ShowcaseInspector {
	/// Where an inspected model floats, in the world's space; the scene moves it when the viewer
	/// stands or sits.
	let stage = Entity()
	private let pivot = Entity()
	private var current: Inspected?
	/// Released models still gliding home, whose hand grab goes back when they land.
	private var landing: [ObjectIdentifier: (task: Task<Void, Never>, manipulation: ManipulationComponent?)] = [:]
	private(set) var spin = ShowcaseSpin()
	var reduceMotion = false

	private struct Inspected {
		let model: Entity
		let home: Entity
		let homeTransform: Transform
		let manipulation: ManipulationComponent?
	}

	static let glide: TimeInterval = 0.35

	init() {
		ShowcaseInspectedComponent.registerComponent()
		ShowcaseHomeComponent.registerComponent()
		stage.name = "InspectStage"
		pivot.name = "InspectPivot"
		stage.addChild(pivot)
	}

	/// The model being inspected, if any.
	var model: Entity? { current?.model }

	/// Seated, a little below eye height and within reach, in front of the front table; standing,
	/// higher and as far in front of the viewer, who is further back in the world.
	func setSeated(_ seated: Bool) {
		stage.position = seated ? [0, 1.05, -0.5] : [0, 1.4, -0.25]
	}

	/// Takes `model` off its stand and floats it on the stage, centered and facing the viewer.
	func inspect(_ model: Entity) {
		guard current?.model !== model else { return }
		release()
		guard let home = model.parent else { return }
		model.stopAllAnimations()
		let homeTransform = model.components[ShowcaseHomeComponent.self]?.transform ?? model.transform
		var manipulation = model.components[ManipulationComponent.self]
		if let pending = landing.removeValue(forKey: ObjectIdentifier(model)) {
			pending.task.cancel()
			manipulation = manipulation ?? pending.manipulation
		}
		let saved = Inspected(model: model, home: home, homeTransform: homeTransform, manipulation: manipulation)
		model.components.remove(ManipulationComponent.self)
		model.components.set(ShowcaseInspectedComponent())
		current = saved
		spin.reset()
		pivot.orientation = spin.orientation
		let center = model.visualBounds(relativeTo: model).center
		model.setParent(pivot, preservingWorldTransform: true)
		model.move(to: Transform(translation: -center), relativeTo: pivot, duration: reduceMotion ? 0 : Self.glide, timingFunction: .easeInOut)
	}

	/// Puts the inspected model back on its stand, as it was.
	func release() {
		guard let saved = current else { return }
		current = nil
		saved.model.components.remove(ShowcaseInspectedComponent.self)
		saved.model.stopAllAnimations()
		saved.model.setParent(saved.home, preservingWorldTransform: true)
		let duration = reduceMotion ? 0 : Self.glide
		saved.model.move(to: saved.homeTransform, relativeTo: saved.home, duration: duration, timingFunction: .easeInOut)
		// The grab comes back once it has landed, so a grab's reset returns it to its stand.
		let key = ObjectIdentifier(saved.model)
		let task = Task { [weak self] in
			try? await Task.sleep(for: .seconds(duration))
			guard !Task.isCancelled, let self, let pending = self.landing.removeValue(forKey: key) else { return }
			if let manipulation = pending.manipulation { saved.model.components.set(manipulation) }
		}
		landing[key] = (task, saved.manipulation)
		spin.reset()
		pivot.orientation = spin.orientation
	}

	/// Whether `entity` is, or is part of, the inspected model.
	func isInspecting(_ entity: Entity) -> Bool {
		guard let model = current?.model else { return false }
		var candidate: Entity? = entity
		while let next = candidate {
			if next === model { return true }
			candidate = next.parent
		}
		return false
	}

	func drag(offset: SIMD2<Float>, at time: TimeInterval) {
		spin.drag(offset: offset, at: time)
		pivot.orientation = spin.orientation
	}

	func endDrag(at time: TimeInterval) {
		spin.endDrag(reduceMotion: reduceMotion, at: time)
	}

	func step(deltaTime dt: TimeInterval) {
		guard current != nil, spin.isMoving else { return }
		spin.step(Float(dt))
		pivot.orientation = spin.orientation
	}

	/// Where the inspected model's card goes: beside it, to the viewer's right.
	var cardPosition: SIMD3<Float> {
		stage.position + [0.24, 0.04, 0]
	}
}
#endif
