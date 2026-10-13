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
