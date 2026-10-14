//
//  SpatialTowerMesh.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd

/// Triangles for a mesh the spatial map builds itself, kept free of RealityKit so they can be
/// checked in tests. Triangles wind counterclockwise seen from the side their normals face.
struct SpatialMeshData {
	var positions: [SIMD3<Float>] = []
	var normals: [SIMD3<Float>] = []
	var indices: [UInt32] = []

	var triangleCount: Int { indices.count / 3 }

	/// A square bar from `a` to `b`, `width` across, with normals pointing out from its axis so it
	/// shades round. The open ends are too small to see.
	mutating func addStrut(from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float) {
		let axis = simd_normalize(b - a)
		let helper: SIMD3<Float> = abs(axis.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
		let u = simd_normalize(simd_cross(axis, helper))
		let v = simd_cross(axis, u)
		let first = UInt32(positions.count)
		// Corners sit half the width times root two from the axis, so the sides are `width` wide.
		let reach: Float = width * 0.5 * Float(2).squareRoot()
		for end in [a, b] {
			for corner in 0..<4 {
				let angle = Float.pi / 4 + Float(corner) * Float.pi / 2
				let out: SIMD3<Float> = u * cos(angle) + v * sin(angle)
				positions.append(end + out * reach)
				normals.append(out)
			}
		}
		for corner in 0..<4 {
			let next = UInt32((corner + 1) % 4), this = UInt32(corner)
			// Corners run from u toward v, counterclockwise seen from `b`, so these face outward.
			indices += [first + this, first + next, first + 4 + this]
			indices += [first + next, first + 4 + next, first + 4 + this]
		}
	}

	/// A flat-shaded slab: `outline` (in x and z, corners in order of increasing angle) from
	/// `bottom` up to `top`, turned `yaw` radians about y and moved to `center`.
	mutating func addPrism(outline: [SIMD2<Float>], bottom: Float, top: Float, yaw: Float = 0, center: SIMD3<Float> = .zero) {
		let turn = simd_quatf(angle: yaw, axis: [0, 1, 0])
		func point(_ p: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { center + turn.act([p.x, y, p.y]) }
		func face(_ corners: [SIMD3<Float>], _ normal: SIMD3<Float>) {
			let first = UInt32(positions.count)
			positions += corners
			normals += Array(repeating: normal, count: corners.count)
			for i in 1..<(corners.count - 1) {
				indices += [first, first + UInt32(i), first + UInt32(i + 1)]
			}
		}
		face(outline.reversed().map { point($0, top) }, turn.act([0, 1, 0]))
		face(outline.map { point($0, bottom) }, turn.act([0, -1, 0]))
		for i in outline.indices {
			let p = outline[i], q = outline[(i + 1) % outline.count]
			let edge = q - p
			let normal = turn.act(simd_normalize(SIMD3(edge.y, 0, -edge.x)))
			face([point(q, bottom), point(p, bottom), point(p, top), point(q, top)], normal)
		}
	}

	mutating func translate(by offset: SIMD3<Float>) {
		positions = positions.map { $0 + offset }
	}
}

/// The lattice radio tower an infrastructure node stands as: three legs tapering from a triangle
/// about 1.4 cm a side, X-braced on every face, a small platform with three panel antennas, and a
/// mast carrying the aviation light. Taller for the roles that cover more of the mesh.
enum SpatialTower {
	static let footprintSide: Float = 0.014
	static let legWidth: Float = 0.0008
	static let braceWidth: Float = 0.00045
	static let mastWidth: Float = 0.0006
	static let beaconRadius: Float = 0.0014
	/// Braced sections up the lattice, each shorter than the one below.
	static let sections = 6
	static let sectionShrink: Float = 0.8
	/// The share of the height the lattice takes; the mast takes the rest.
	static let latticeShare: Float = 0.72
	/// Half width of the lattice's top as a share of the footprint's.
	static let topShare: Float = 0.16
	static let triangleBudget = 600

	/// Height from the foot of the legs to the top of the light, nil for roles drawn as a pin.
	static func height(for role: DeviceRoles?) -> Float? {
		switch role {
		case .router: 0.05
		case .routerLate: 0.045
		case .repeater: 0.04
		case .clientBase: 0.035
		default: nil
		}
	}

	/// Where the light's center sits, the light just touching the top.
	static func beaconCenter(height: Float) -> Float {
		height - beaconRadius
	}

	/// Leg directions in x and z: one toward the back, two toward the front corners.
	private static let legAngles: [Float] = [-.pi / 2, .pi / 6, 5 * .pi / 6]

	/// The heights the bracing meets the legs at, from the ground to the lattice top.
	static func levels(latticeHeight: Float) -> [Float] {
		let first = latticeHeight * (1 - sectionShrink) / (1 - pow(sectionShrink, Float(sections)))
		var result: [Float] = [0]
		var step = first
		for _ in 0..<sections {
			result.append(min(result.last! + step, latticeHeight))
			step *= sectionShrink
		}
		result[result.count - 1] = latticeHeight
		return result
	}

	/// The whole tower but the light, standing on y = 0 with the legs centered on the origin.
	static func geometry(height: Float) -> SpatialMeshData {
		var mesh = SpatialMeshData()
		let lattice = height * latticeShare
		let baseRadius = footprintSide / Float(3).squareRoot()
		let topRadius = baseRadius * topShare
		func corner(_ leg: Int, _ y: Float) -> SIMD3<Float> {
			let radius = baseRadius + (topRadius - baseRadius) * y / lattice
			let angle = legAngles[leg % 3]
			return [radius * cos(angle), y, radius * sin(angle)]
		}
		for leg in 0..<3 {
			mesh.addStrut(from: corner(leg, 0), to: corner(leg, lattice), width: legWidth)
		}
		let levels = levels(latticeHeight: lattice)
		for section in 0..<(levels.count - 1) {
			let low = levels[section], high = levels[section + 1]
			for face in 0..<3 {
				mesh.addStrut(from: corner(face, low), to: corner(face + 1, high), width: braceWidth)
				mesh.addStrut(from: corner(face + 1, low), to: corner(face, high), width: braceWidth)
				if section > 0 {
					mesh.addStrut(from: corner(face, low), to: corner(face + 1, low), width: braceWidth)
				}
			}
		}
		// A triangular deck on the lattice top, wider than the legs there.
		let deckRadius = topRadius * 2.4
		let deck = legAngles.map { SIMD2(deckRadius * cos($0), deckRadius * sin($0)) }
		mesh.addPrism(outline: deck, bottom: lattice - 0.0005, top: lattice)
		// The mast up to the light, and three panel antennas round it facing between the legs.
		mesh.addStrut(from: [0, lattice - 0.0005, 0], to: [0, beaconCenter(height: height), 0], width: mastWidth)
		let panel: [SIMD2<Float>] = [[-0.0002, -0.0006], [0.0002, -0.0006], [0.0002, 0.0006], [-0.0002, 0.0006]]
		let panelBottom = lattice + 0.0012
		for leg in 0..<3 {
			let angle = legAngles[leg] + .pi / 3
			let center = SIMD3(0.0011 * cos(angle), 0, 0.0011 * sin(angle))
			mesh.addPrism(outline: panel, bottom: panelBottom, top: panelBottom + 0.0042, yaw: -angle, center: center)
		}
		// The bars' corners stick a hair below the ground where the legs lean in; stand it on y = 0.
		let lowest = mesh.positions.map(\.y).min() ?? 0
		mesh.translate(by: [0, -lowest, 0])
		return mesh
	}
}

/// The red aviation light on top of each tower: about a second on and a second off with a soft
/// fade, every tower on one clock but a little out of step with its neighbors.
enum SpatialTowerBeacon {
	static let period: Double = 2
	static let fade: Double = 0.3
	/// The most a node's light runs ahead of the shared clock.
	static let maxOffset: Double = 0.6

	/// The light's brightness, 0 to 1, at `time` seconds on the shared clock.
	static func brightness(time: Double, offset: Double) -> Float {
		var phase = (time + offset).truncatingRemainder(dividingBy: period)
		if phase < 0 { phase += period }
		let on = period / 2
		if phase < fade { return smooth(phase / fade) }
		if phase < on { return 1 }
		if phase < on + fade { return smooth(1 - (phase - on) / fade) }
		return 0
	}

	/// A node's fixed lead on the shared clock, from its number.
	static func offset(for nodeNum: Int64) -> Double {
		let mixed = UInt32(truncatingIfNeeded: nodeNum) &* 2_654_435_761
		return Double(mixed % 1_000) / 1_000 * maxOffset
	}

	private static func smooth(_ x: Double) -> Float {
		let t = min(max(x, 0), 1)
		return Float(t * t * (3 - 2 * t))
	}
}

/// The rings that ripple out from a tower's antenna when that node is heard: a few thin rings a
/// moment apart, each widening and fading.
enum SpatialSignalRings {
	static let count = 3
	static let stagger: Double = 0.3
	static let duration: Double = 1.4
	static let startRadius: Float = 0.002
	static let endRadius: Float = 0.026
	static let peakOpacity: Float = 1
	/// The ring mesh's inner edge as a share of its outer edge.
	static let innerShare: Float = 0.8

	static var burstDuration: Double { stagger * Double(count - 1) + duration }

	/// A tower ripples at most every couple of seconds, and only a few start each second.
	static func limiter() -> PulseRateLimiter {
		PulseRateLimiter(capacity: 4, refillPerSecond: 2, perSenderInterval: 2.5)
	}

	/// Ring `index`'s radius and opacity `elapsed` seconds into a burst; nil before it starts and
	/// once it has faded.
	static func ring(_ index: Int, elapsed: Double) -> (radius: Float, opacity: Float)? {
		let t = (elapsed - Double(index) * stagger) / duration
		guard t >= 0, t < 1 else { return nil }
		let grown = Float(1 - (1 - t) * (1 - t))
		let left = Float(1 - t)
		return (startRadius + (endRadius - startRadius) * grown, peakOpacity * left * left.squareRoot())
	}

	/// A flat ring of radius 1 in the x-z plane, faced both up and down.
	static func ringMesh(segments: Int = 48) -> SpatialMeshData {
		var mesh = SpatialMeshData()
		for side: Float in [1, -1] {
			let first = UInt32(mesh.positions.count)
			for i in 0..<segments {
				let angle = Float(i) / Float(segments) * 2 * .pi
				let direction = SIMD3(cos(angle), 0, sin(angle))
				mesh.positions += [direction, direction * innerShare]
				mesh.normals += [[0, side, 0], [0, side, 0]]
			}
			for i in 0..<segments {
				let outer = first + UInt32(2 * i), inner = outer + 1
				let nextOuter = first + UInt32(2 * ((i + 1) % segments)), nextInner = nextOuter + 1
				if side > 0 {
					mesh.indices += [outer, inner, nextOuter, nextOuter, inner, nextInner]
				} else {
					mesh.indices += [outer, nextOuter, inner, nextOuter, nextInner, inner]
				}
			}
		}
		return mesh
	}
}
