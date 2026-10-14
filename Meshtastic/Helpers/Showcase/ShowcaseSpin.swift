//
//  ShowcaseSpin.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd

/// Turns a model held up for inspection, like a globe: dragging sideways spins it about the
/// vertical, dragging up or down tips it toward or away from the viewer. Let go mid-drag and it
/// keeps turning for a moment, slowing down.
struct ShowcaseSpin: Equatable, Sendable {
	/// Radians of turn per meter the hand moves; a 10 cm drag is about 85°.
	static let radiansPerMeter: Float = 15
	/// How far it tips, so it never ends up upside down.
	static let maxPitch: Float = 1.3
	/// How quickly a flick dies away, per second.
	static let damping: Float = 3.5
	/// Below this a flick has stopped, in radians per second.
	static let restSpeed: Float = 0.05

	private(set) var yaw: Float = 0
	private(set) var pitch: Float = 0
	/// Turning speed after a release: x is yaw, y is pitch, in radians per second.
	private(set) var velocity: SIMD2<Float> = .zero
	private var dragStart: SIMD2<Float>?
	private var lastDrag: (offset: SIMD2<Float>, time: TimeInterval)?

	/// Yaw about the vertical, then pitch about the horizontal, so tipping stays toward the viewer
	/// however far it has spun.
	var orientation: simd_quatf {
		simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
	}

	var isMoving: Bool { dragStart != nil || simd_length(velocity) > Self.restSpeed }

	/// `offset` is how far the hand has moved since the drag began, in meters: x to the right,
	/// y up.
	mutating func drag(offset: SIMD2<Float>, at time: TimeInterval) {
		if dragStart == nil {
			dragStart = SIMD2(yaw, pitch)
			velocity = .zero
		}
		guard let start = dragStart else { return }
		yaw = start.x + offset.x * Self.radiansPerMeter
		pitch = min(max(start.y - offset.y * Self.radiansPerMeter, -Self.maxPitch), Self.maxPitch)
		if let last = lastDrag, time > last.time {
			let speed = (offset - last.offset) * Self.radiansPerMeter / Float(time - last.time)
			velocity = SIMD2(speed.x, -speed.y)
		}
		lastDrag = (offset, time)
	}

	/// Ends the drag; it coasts on unless motion is reduced.
	mutating func endDrag(reduceMotion: Bool) {
		dragStart = nil
		lastDrag = nil
		if reduceMotion { velocity = .zero }
	}

	/// Advances a coast after a release.
	mutating func step(_ dt: Float) {
		guard dragStart == nil, simd_length(velocity) > Self.restSpeed else {
			if dragStart == nil { velocity = .zero }
			return
		}
		yaw += velocity.x * dt
		pitch = min(max(pitch + velocity.y * dt, -Self.maxPitch), Self.maxPitch)
		velocity *= exp(-Self.damping * dt)
	}

	mutating func reset() {
		self = ShowcaseSpin()
	}

	static func == (lhs: ShowcaseSpin, rhs: ShowcaseSpin) -> Bool {
		lhs.yaw == rhs.yaw && lhs.pitch == rhs.pitch && lhs.velocity == rhs.velocity && lhs.dragStart == rhs.dragStart
	}
}
