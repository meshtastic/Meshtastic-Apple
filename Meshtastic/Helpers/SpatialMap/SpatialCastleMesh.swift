//
//  SpatialCastleMesh.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//
import Foundation
import simd

extension SpatialMeshData {
	/// A flat-sided frustum: a regular polygon of `sides` about the vertical through `center`,
	/// `bottomRadius` to its corners at `bottom` and `topRadius` at `top`, capped at both ends, its
	/// first corner `turn` radians round from +x.
	mutating func addFrustum(sides: Int, bottomRadius: Float, topRadius: Float, bottom: Float, top: Float, center: SIMD3<Float> = .zero, turn: Float = 0) {
		func corner(_ i: Int, _ radius: Float, _ y: Float) -> SIMD3<Float> {
			let angle = turn + Float(i) * 2 * .pi / Float(sides)
			return center + SIMD3(cos(angle) * radius, y, sin(angle) * radius)
		}
		func face(_ points: [SIMD3<Float>]) {
			// A cone's sides meet at its tip; drop the repeated corner so the normal can be found.
			var corners: [SIMD3<Float>] = []
			for point in points where corners.last != point {
				corners.append(point)
			}
			let normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
			let first = UInt32(positions.count)
			positions += corners
			normals += Array(repeating: normal, count: corners.count)
			for i in 1..<(corners.count - 1) {
				indices += [first, first + UInt32(i), first + UInt32(i + 1)]
			}
		}
		for i in 0..<sides {
			face([corner(i, bottomRadius, bottom), corner(i, topRadius, top), corner(i + 1, topRadius, top), corner(i + 1, bottomRadius, bottom)])
		}
		if topRadius > 0 {
			face((0..<sides).reversed().map { corner($0, topRadius, top) })
		}
		if bottomRadius > 0 {
			face((0..<sides).map { corner($0, bottomRadius, bottom) })
		}
	}

	/// A flat slab standing on a wall: `outline` (across the face to the right as seen from outside,
	/// and up; corners counterclockwise, convex) from `back` to `front` out from the center, on the
	/// face that looks along +z turned `side` quarter turns about y.
	mutating func addPanel(outline: [SIMD2<Float>], back: Float, front: Float, side: Int) {
		let turn = simd_quatf(angle: Float(side) * .pi / 2, axis: [0, 1, 0])
		func point(_ p: SIMD2<Float>, _ depth: Float) -> SIMD3<Float> { turn.act([p.x, p.y, depth]) }
		func face(_ corners: [SIMD3<Float>], _ normal: SIMD3<Float>) {
			let first = UInt32(positions.count)
			positions += corners
			normals += Array(repeating: normal, count: corners.count)
			for i in 1..<(corners.count - 1) {
				indices += [first, first + UInt32(i), first + UInt32(i + 1)]
			}
		}
		face(outline.map { point($0, front) }, turn.act([0, 0, 1]))
		face(outline.reversed().map { point($0, back) }, turn.act([0, 0, -1]))
		for i in outline.indices {
			let p = outline[i], q = outline[(i + 1) % outline.count]
			let edge = q - p
			let normal = turn.act(simd_normalize(SIMD3(edge.y, -edge.x, 0)))
			face([point(p, front), point(p, back), point(q, back), point(q, front)], normal)
		}
	}
}

/// The castle tower the cinema's castle room stands on, drawn on the spatial map at the summit
/// chosen for it, as the fire lookout is for the lookout's: a square keep of dressed stone on a
/// battered plinth, with string courses, arrow slits low down, arched windows in stone surrounds
/// above them lit from inside, an arched door at its foot, a crenellated parapet round its open top,
/// a round bartizan corbelled out under each open corner, and a banner on a pole over the back left
/// one. About as tall as the lookout and on about its footprint, so it steps aside from a node on
/// the same summit the same way.
enum SpatialCastle {
	/// The parts drawn in their own material.
	enum Part: CaseIterable {
		/// The walls, in the stone chosen, with its blocks drawn on (`textureCoordinates`).
		case stone
		/// The arrow slits.
		case opening
		/// The windows' glass, lit from inside.
		case window
		case wood
		case banner
		case metal
	}

	/// The keep, from the ground to its roof.
	static let keepHalf: Float = 0.0064
	static let keepHeight: Float = 0.036
	static let plinthHalf: Float = 0.0072
	static let plinthHeight: Float = 0.003
	/// The string courses, the lower one dividing the slits below from the windows above.
	static let courses: [Float] = [0.0144, keepHeight - 0.0006]
	/// The parapet round the roof: its wall, then the merlons on it.
	static let parapetThickness: Float = 0.0011
	static let parapetHeight: Float = 0.0022
	static let merlonHeight: Float = 0.0016
	static let merlonsPerSide = 4
	/// The bartizans on the corners.
	static let bartizanRadius: Float = 0.0021
	static let bartizanCorbel: Float = 0.004
	/// The banner pole above the parapet, and the banner on it.
	static let poleHeight: Float = 0.011
	static let bannerWidth: Float = 0.0032
	static let bannerHeight: Float = 0.0045
	/// The stone's blocks: how long and how high each is on the model, larger than life so they
	/// show at the map's scale.
	static let blockLength: Float = 0.0016
	static let blockHeight: Float = 0.0008
	/// The block texture is this many blocks across and courses up, so neighbors differ.
	static let tileBlocks = 4
	static let triangleBudget = 2_600

	static var parapetTop: Float { keepHeight + parapetHeight }
	/// From the ground to the top of the banner pole.
	static var height: Float { parapetTop + poleHeight }

	/// A window or door: its middle across the face, its sill, how wide it is and how tall to the
	/// top of its round arch.
	struct Opening {
		let along: Float
		let bottom: Float
		let width: Float
		let height: Float

		/// The outline, counterclockwise from the bottom left, grown by `margin` all round.
		func outline(margin: Float = 0) -> [SIMD2<Float>] {
			let half = width / 2 + margin
			let springing = bottom + height - width / 2
			var points: [SIMD2<Float>] = [[along - half, bottom - margin], [along + half, bottom - margin]]
			let segments = 8
			for step in 0...segments {
				let angle = Float(step) * .pi / Float(segments)
				points.append([along + cos(angle) * half, springing + sin(angle) * half])
			}
			return points
		}
	}

	/// The arched windows on every face: a pair on the floor above the string course, and a wide
	/// one under the parapet split by a mullion.
	static let windows = [
		Opening(along: -0.003, bottom: 0.0172, width: 0.0016, height: 0.0042),
		Opening(along: 0.003, bottom: 0.0172, width: 0.0016, height: 0.0042),
		Opening(along: 0, bottom: 0.0255, width: 0.0028, height: 0.0055)
	]
	/// The arrow slits below the string course: either side of the door in front, in pairs elsewhere.
	static let slits: [(along: Float, bottom: Float)] = [(-0.0036, 0.008), (0.0036, 0.008)]
	static let door = Opening(along: 0, bottom: plinthHeight, width: 0.0028, height: 0.0062)

	/// The whole castle standing on y = 0, centered on the origin, its front toward +z.
	static func geometry() -> [Part: SpatialMeshData] {
		var parts: [Part: SpatialMeshData] = [:]
		for part in Part.allCases { parts[part] = SpatialMeshData() }
		func add(_ part: Part, _ build: (inout SpatialMeshData) -> Void) {
			build(&parts[part, default: SpatialMeshData()])
		}
		func square(_ half: Float) -> [SIMD2<Float>] {
			[[-half, -half], [half, -half], [half, half], [-half, half]]
		}
		/// A box `along` wide on the side facing +z turned `side` quarter turns, `out` from the center.
		func onSide(_ side: Int, along: Float, width: Float, depth: Float, out: Float) -> (outline: [SIMD2<Float>], yaw: Float) {
			let outline: [SIMD2<Float>] = [[along - width / 2, out - depth / 2], [along + width / 2, out - depth / 2], [along + width / 2, out + depth / 2], [along - width / 2, out + depth / 2]]
			return (outline, Float(side) * .pi / 2)
		}

		// The keep on its battered plinth, with string courses standing proud of it.
		add(.stone) { mesh in
			mesh.addPrism(outline: square(plinthHalf), bottom: 0, top: plinthHeight)
			mesh.addFrustum(sides: 4, bottomRadius: plinthHalf * Float(2).squareRoot(), topRadius: keepHalf * Float(2).squareRoot(), bottom: plinthHeight, top: plinthHeight + 0.0012, turn: .pi / 4)
			mesh.addPrism(outline: square(keepHalf), bottom: plinthHeight, top: keepHeight)
			for y in courses {
				mesh.addPrism(outline: square(keepHalf + 0.0003), bottom: y - 0.0005, top: y)
			}
		}

		// The parapet: a wall round the roof's edge, merlons along it.
		add(.stone) { mesh in
			let out = keepHalf - parapetThickness / 2
			for side in 0..<4 {
				let wall = onSide(side, along: 0, width: 2 * keepHalf - parapetThickness, depth: parapetThickness, out: out)
				mesh.addPrism(outline: wall.outline, bottom: keepHeight, top: parapetTop, yaw: wall.yaw)
				let spacing = 2 * keepHalf / Float(merlonsPerSide)
				for index in 0..<merlonsPerSide {
					let along = -keepHalf + spacing * (Float(index) + 0.5)
					let merlon = onSide(side, along: along, width: spacing * 0.55, depth: parapetThickness, out: out)
					mesh.addPrism(outline: merlon.outline, bottom: parapetTop, top: parapetTop + merlonHeight, yaw: merlon.yaw)
				}
			}
		}

		// A bartizan under each corner: corbelled out on a cone, its wall up to the parapet's and
		// open on top, as the cinema's corners are.
		let corners: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
		add(.stone) { mesh in
			for sign in corners {
				let center = SIMD3(sign.x * keepHalf, 0, sign.y * keepHalf)
				let base = keepHeight - 0.006
				mesh.addFrustum(sides: 10, bottomRadius: 0.0004, topRadius: bartizanRadius, bottom: base - bartizanCorbel, top: base, center: center)
				mesh.addFrustum(sides: 10, bottomRadius: bartizanRadius, topRadius: bartizanRadius, bottom: base, top: parapetTop, center: center)
			}
		}

		// The windows: a stone surround standing proud of the wall with a sill under it, the glass
		// inside it, and the wide one's mullion. The door gets a surround too.
		add(.stone) { mesh in
			for side in 0..<4 {
				for window in windows {
					mesh.addPanel(outline: window.outline(margin: 0.00035), back: keepHalf - 0.0001, front: keepHalf + 0.00022, side: side)
					let sill: [SIMD2<Float>] = [[window.along - window.width / 2 - 0.0006, window.bottom - 0.0007], [window.along + window.width / 2 + 0.0006, window.bottom - 0.0007], [window.along + window.width / 2 + 0.0006, window.bottom - 0.00035], [window.along - window.width / 2 - 0.0006, window.bottom - 0.00035]]
					mesh.addPanel(outline: sill, back: keepHalf - 0.0001, front: keepHalf + 0.0005, side: side)
					if window.width > 0.002 {
						let mullion: [SIMD2<Float>] = [[window.along - 0.00018, window.bottom], [window.along + 0.00018, window.bottom], [window.along + 0.00018, window.bottom + window.height - 0.0002], [window.along - 0.00018, window.bottom + window.height - 0.0002]]
						mesh.addPanel(outline: mullion, back: keepHalf, front: keepHalf + 0.0003, side: side)
					}
				}
			}
			mesh.addPanel(outline: door.outline(margin: 0.0004), back: keepHalf - 0.0001, front: keepHalf + 0.00025, side: 0)
		}
		add(.window) { mesh in
			for side in 0..<4 {
				for window in windows {
					mesh.addPanel(outline: window.outline(), back: keepHalf, front: keepHalf + 0.00026, side: side)
				}
			}
		}
		add(.opening) { mesh in
			for side in 0..<4 {
				for slit in slits {
					let outline: [SIMD2<Float>] = [[slit.along - 0.00025, slit.bottom], [slit.along + 0.00025, slit.bottom], [slit.along + 0.00025, slit.bottom + 0.003], [slit.along - 0.00025, slit.bottom + 0.003]]
					mesh.addPanel(outline: outline, back: keepHalf - 0.0001, front: keepHalf + 0.0001, side: side)
				}
			}
		}

		// The door, set in its surround, and the banner pole.
		let pole = SIMD3(-keepHalf, 0, -keepHalf)
		add(.wood) { mesh in
			mesh.addPanel(outline: door.outline(), back: keepHalf, front: keepHalf + 0.0003, side: 0)
			mesh.addStrut(from: pole + [0, parapetTop - 0.001, 0], to: pole + [0, height - 0.0004, 0], width: 0.0003)
			// The crossbar the banner hangs from, across the castle's back-left corner.
			let across = simd_normalize(SIMD3<Float>(1, 0, -1)) * (bannerWidth / 2 + 0.0002)
			let bar = pole + [0, height - 0.0012, 0]
			mesh.addStrut(from: bar - across, to: bar + across, width: 0.00022)
		}
		add(.banner) { mesh in
			let across = simd_normalize(SIMD3<Float>(1, 0, -1))
			let top = height - 0.0014
			let half = across * bannerWidth / 2
			let corners: [SIMD3<Float>] = [pole - half + [0, top - bannerHeight, 0], pole + half + [0, top - bannerHeight, 0], pole + half + [0, top, 0], pole - half + [0, top, 0]]
			// Both faces, so it shows from either side.
			let normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
			for (order, facing) in [([0, 1, 2, 3], normal), ([3, 2, 1, 0], -normal)] {
				let first = UInt32(mesh.positions.count)
				mesh.positions += order.map { corners[$0] }
				mesh.normals += Array(repeating: facing, count: 4)
				mesh.indices += [first, first + 1, first + 2, first, first + 2, first + 3]
			}
		}
		add(.metal) { $0.addFrustum(sides: 6, bottomRadius: 0.0004, topRadius: 0, bottom: height - 0.0004, top: height, center: pole) }
		return parts
	}

	/// Where each of `mesh`'s points falls on the stone's block texture, one tile `tileBlocks`
	/// blocks across and as many courses up: across a wall and up it on the walls, and flat on tops and undersides, picked
	/// by the way the point's face looks. Each face's points are its own, so the blocks follow
	/// round the corners.
	static func textureCoordinates(_ mesh: SpatialMeshData) -> [SIMD2<Float>] {
		zip(mesh.positions, mesh.normals).map { position, normal in
			let n = abs(normal)
			let flat: SIMD2<Float>
			if n.y >= n.x && n.y >= n.z {
				flat = [position.x, position.z]
			} else if n.x >= n.z {
				flat = [position.z, position.y]
			} else {
				flat = [position.x, position.y]
			}
			return SIMD2(flat.x / blockLength, flat.y / blockHeight) / Float(tileBlocks)
		}
	}
}
