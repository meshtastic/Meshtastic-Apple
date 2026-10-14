//
//  SpatialWheel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import Foundation
import simd

/// Turns a drag into a rotation that follows the hand around the middle of the table, like
/// turning a wheel. Points are x/z in the table's own unrotated frame, centered on the disk.
/// Turns a sideways hand movement into a spin. A look-and-pinch drag moves the hand only a few
/// centimeters, so following its angle around the middle barely turned the map; this turns the map
/// by the distance moved, in the direction that carries the grabbed point along with the hand.
enum SpatialWheelSpin {
	/// Radians per meter of hand travel, per meter of disk radius: twice the rim's own arc.
	static let gain: Float = 2

	/// Yaw change for a drag that started at `start` and is now at `current` (table x/z, meters,
	/// +z toward the viewer). Grabbing the near half and moving right turns the map the other way
	/// from grabbing the far half, the way a wheel turns under the hand.
	static func yawDelta(start: SIMD2<Float>, current: SIMD2<Float>, diskRadius: Float) -> Float {
		let dx = current.x - start.x
		guard dx.isFinite else { return 0 }
		let side: Float = start.y >= 0 ? 1 : -1
		return side * dx * gain / max(diskRadius, 0.1)
	}
}

struct SpatialWheelDrag: Equatable, Sendable {
	/// Points closer to the center than this, in meters, give no usable angle and are skipped.
	static let deadZone: Float = 0.03

	let startYaw: Float
	private var lastAngle: Float?
	/// Total turn since the drag began, which can run past a full turn.
	private(set) var turned: Float = 0

	var yaw: Float { startYaw + turned }

	init(startYaw: Float, x: Float, z: Float) {
		self.startYaw = startYaw
		lastAngle = Self.angle(x: x, z: z)
	}

	/// Moves the drag to a new point and returns the yaw to show.
	mutating func update(x: Float, z: Float) -> Float {
		guard let angle = Self.angle(x: x, z: z) else { return yaw }
		if let lastAngle { turned += Self.wrapped(angle - lastAngle) }
		lastAngle = angle
		return yaw
	}

	/// The angle of a point around the center that a yaw about +y adds to: turning the table by
	/// `yaw` moves a point from angle `a` to `a + yaw`. Nil inside the dead zone.
	static func angle(x: Float, z: Float) -> Float? {
		guard x.isFinite, z.isFinite, x * x + z * z >= deadZone * deadZone else { return nil }
		return atan2(-z, x)
	}

	/// An angle brought into -π...π.
	static func wrapped(_ angle: Float) -> Float {
		var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
		if a > .pi { a -= 2 * .pi }
		if a <= -.pi { a += 2 * .pi }
		return a
	}
}

/// Sizes of the compass bezel and the handles around the disk, in meters. Everything fits in the
/// margin the volume fit leaves around the rim.
enum SpatialWheelLayout {
	/// Gap between the disk's edge and the bezel.
	static let gap: Float = 0.001
	/// Radial width of the bezel.
	static let bezelWidth: Float = 0.022
	/// How far the bezel's top stands above the highest point of the map's edge.
	static let bezelLift: Float = 0.005
	/// Size of the chamfer on the bezel's top edges.
	static let chamfer: Float = 0.004
	/// The bezel never stands taller than this above the table's zero height, so a hill on one
	/// part of the edge doesn't raise a wall that hides the rest of it.
	static let maximumTop: Float = 0.03
	static let handleCount = 8
	static let spokeLength: Float = 0.03
	static let spokeRadius: Float = 0.0035
	static let knobRadius: Float = 0.009

	/// Distance from the center to the middle of a knob.
	static func knobDistance(diskRadius: Float) -> Float {
		diskRadius + gap + bezelWidth + spokeLength
	}

	/// How far the whole wheel reaches past the disk's edge.
	static var reach: Float { gap + bezelWidth + spokeLength + knobRadius }

	/// Handle angles in the yaw sense (see `SpatialWheelDrag.angle`), set between the compass
	/// points so none sits under a letter.
	static var handleAngles: [Float] {
		(0..<handleCount).map { (Float($0) + 0.5) * 2 * .pi / Float(handleCount) }
	}

	/// x/z of a point at a distance from the center at an angle in the yaw sense.
	static func point(distance: Float, angle: Float) -> SIMD2<Float> {
		SIMD2(distance * cos(angle), -distance * sin(angle))
	}

	/// The compass points and where they sit on the bezel. North is -z on the map, east +x.
	static let compassPoints: [(letter: String, angle: Float)] = [
		("N", .pi / 2), ("E", 0), ("S", -.pi / 2), ("W", .pi)
	]
}

/// A raised ring with chamfered top edges: inner wall, inner chamfer, flat top, outer chamfer,
/// outer wall. Each face has its own vertices so the edges stay crisp.
struct SpatialBezelMesh: Sendable {
	let positions: [SIMD3<Float>]
	let normals: [SIMD3<Float>]
	let indices: [UInt32]

	init(innerRadius: Float, width: Float, bottom: Float, top: Float, chamfer: Float, segments: Int = 128) {
		let c = min(chamfer, width / 3, max(top - bottom, 0) / 2)
		let inner = innerRadius, outer = innerRadius + width
		let wallTop = top - c
		// Each face's profile as (radius, height) from its first edge to its second, with the
		// face's outward normal as (radial, up).
		struct Face { let a: SIMD2<Float>; let b: SIMD2<Float>; let normal: SIMD2<Float> }
		let faces = [
			Face(a: SIMD2(inner, wallTop), b: SIMD2(inner, bottom), normal: SIMD2(-1, 0)),
			Face(a: SIMD2(inner + c, top), b: SIMD2(inner, wallTop), normal: simd_normalize(SIMD2(-1, 1))),
			Face(a: SIMD2(outer - c, top), b: SIMD2(inner + c, top), normal: SIMD2(0, 1)),
			Face(a: SIMD2(outer, wallTop), b: SIMD2(outer - c, top), normal: simd_normalize(SIMD2(1, 1))),
			Face(a: SIMD2(outer, bottom), b: SIMD2(outer, wallTop), normal: SIMD2(1, 0))
		]
		let n = max(segments, 3)
		var positions: [SIMD3<Float>] = []
		var normals: [SIMD3<Float>] = []
		var indices: [UInt32] = []
		positions.reserveCapacity(faces.count * (n + 1) * 2)
		indices.reserveCapacity(faces.count * n * 6)
		for face in faces {
			let a = face.a, b = face.b, normal = face.normal
			let base = UInt32(positions.count)
			for s in 0...n {
				let angle = Float(s) / Float(n) * 2 * .pi
				let direction = SIMD2(cos(angle), -sin(angle))
				for p in [a, b] {
					positions.append(SIMD3(direction.x * p.x, p.y, direction.y * p.x))
				}
				let radial = SIMD3(direction.x * normal.x, normal.y, direction.y * normal.x)
				normals.append(radial)
				normals.append(radial)
			}
			// Front faces wind counter-clockwise seen from the side the normal points to.
			for s in 0..<n {
				let a0 = base + UInt32(s * 2), b0 = a0 + 1, a1 = a0 + 2, b1 = a0 + 3
				indices.append(contentsOf: [a0, a1, b0, a1, b1, b0])
			}
		}
		self.positions = positions
		self.normals = normals
		self.indices = indices
	}
}

/// The wheel's turn as it is shown, stepped once per frame. A drag sets where the wheel is
/// heading; each frame eases the shown turn toward it, and a release with some speed keeps the
/// wheel spinning until friction stops it. Times are in seconds, angles in radians.
struct SpatialWheelMotion: Equatable, Sendable {
	/// How quickly the shown turn catches up with the hand. Short enough not to feel like lag,
	/// long enough to smooth out uneven hand samples.
	static let followTimeConstant: Double = 0.07
	/// The slower ease a double tap uses to swing back to north.
	static let resetTimeConstant: Double = 0.1
	/// How quickly a released spin slows; it is all but stopped within a second.
	static let frictionTimeConstant: Double = 0.22
	/// The span of hand movement the release speed is measured over.
	static let velocityWindow: Double = 0.1
	/// Releases slower than this don't coast, so letting go of a held wheel leaves it still.
	static let minimumFlickSpeed: Float = 0.6
	/// A coast slows to this and stops.
	static let stopSpeed: Float = 0.15
	static let maximumSpeed: Float = 8

	/// The turn on screen.
	private(set) var shown: Float = 0
	/// Where the shown turn is heading.
	private(set) var target: Float = 0
	/// Speed of a released spin, zero when not coasting.
	private(set) var velocity: Float = 0
	private(set) var isResetting = false
	private var samples: [(time: Double, yaw: Float)] = []

	var isCoasting: Bool { velocity != 0 }
	/// True while there is still something to move.
	var isMoving: Bool { isCoasting || shown != target }

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.shown == rhs.shown && lhs.target == rhs.target && lhs.velocity == rhs.velocity && lhs.isResetting == rhs.isResetting
	}

	/// Moves `current` toward `target` by the share of the gap one step of `dt` closes, the same
	/// at any frame rate.
	static func eased(_ current: Float, toward target: Float, dt: Double, timeConstant: Double) -> Float {
		guard dt > 0, timeConstant > 0 else { return target }
		let share = Float(1 - exp(-dt / timeConstant))
		let next = current + (target - current) * share
		return abs(target - next) < 1e-4 ? target : next
	}

	/// The speed over the samples in the last `window` before `now`, zero without enough of them.
	/// The span runs to `now`, so a hand that stopped before letting go reads as slower.
	static func velocity(of samples: [(time: Double, yaw: Float)], at now: Double, window: Double = velocityWindow) -> Float {
		let recent = samples.filter { $0.time >= now - window }
		guard let first = recent.first, let last = recent.last, last.time - first.time >= 0.01 else { return 0 }
		let span = max(last.time, now) - first.time
		return (last.yaw - first.yaw) / Float(span)
	}

	/// A coasting speed after friction has acted for `dt`, zero once it is slow enough to stop.
	static func decayed(_ velocity: Float, dt: Double) -> Float {
		let next = velocity * Float(exp(-max(dt, 0) / frictionTimeConstant))
		return abs(next) < stopSpeed ? 0 : next
	}

	/// Halts the wheel where it is and returns the turn a drag should start from.
	mutating func grab() -> Float {
		velocity = 0
		isResetting = false
		target = shown
		samples.removeAll(keepingCapacity: true)
		return target
	}

	/// The hand has moved the wheel to `yaw` at `time`.
	mutating func drag(to yaw: Float, at time: Double) {
		target = yaw
		samples.append((time, yaw))
		if let first = samples.first, first.time < time - Self.velocityWindow * 2 { samples.removeFirst() }
	}

	/// The hand let go at `time`: a quick enough spin carries on.
	mutating func release(at time: Double) {
		let speed = Self.velocity(of: samples, at: time)
		samples.removeAll(keepingCapacity: true)
		velocity = abs(speed) < Self.minimumFlickSpeed ? 0 : min(max(speed, -Self.maximumSpeed), Self.maximumSpeed)
	}

	/// Stops a coast where it is. A swing back to north carries on, since the taps of the double
	/// tap that started it also arrive here.
	mutating func stop() {
		guard !isResetting else { return }
		velocity = 0
		isResetting = false
		target = shown
	}

	/// Swings back to north the short way round.
	mutating func reset() {
		velocity = 0
		samples.removeAll(keepingCapacity: true)
		let turns = (shown / (2 * .pi)).rounded()
		shown -= turns * 2 * .pi
		target = 0
		isResetting = true
	}

	/// Advances one frame and returns true when the shown turn changed.
	mutating func step(dt: Double) -> Bool {
		guard isMoving, dt > 0 else { return false }
		if isCoasting {
			target += velocity * Float(dt)
			velocity = Self.decayed(velocity, dt: dt)
		}
		let before = shown
		shown = Self.eased(shown, toward: target, dt: dt, timeConstant: isResetting ? Self.resetTimeConstant : Self.followTimeConstant)
		if shown == target, !isCoasting { isResetting = false }
		return shown != before
	}
}
