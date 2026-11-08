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
}

/// The castle tower the cinema's castle room stands on, drawn on the spatial map at the summit
/// chosen for it, as the fire lookout is for the lookout's: a square stone keep on a battered
/// plinth, with string courses and arrow slits, a door at its foot, a crenellated parapet round its
/// open top, a round bartizan corbelled out from each corner, and a banner on a pole over the back
/// left one. About as tall as the lookout and on about its footprint, so it steps aside from a node
/// on the same summit the same way.
enum SpatialCastle {
	/// The parts drawn in their own material.
	enum Part: CaseIterable {
		/// The walls, in the stone chosen.
		case stone
		/// The arrow slits and the doorway's shadow.
		case opening
		case wood
		case banner
		case metal
	}

	/// The keep, from the ground to its roof.
	static let keepHalf: Float = 0.0064
	static let keepHeight: Float = 0.036
	static let plinthHalf: Float = 0.0072
	static let plinthHeight: Float = 0.003
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
	static let triangleBudget = 1_200

	static var parapetTop: Float { keepHeight + parapetHeight }
	/// From the ground to the top of the banner pole.
	static var height: Float { parapetTop + poleHeight }

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

		// The keep on its battered plinth, with two string courses standing proud of it.
		add(.stone) { mesh in
			mesh.addPrism(outline: square(plinthHalf), bottom: 0, top: plinthHeight)
			mesh.addFrustum(sides: 4, bottomRadius: plinthHalf * Float(2).squareRoot(), topRadius: keepHalf * Float(2).squareRoot(), bottom: plinthHeight, top: plinthHeight + 0.0012, turn: .pi / 4)
			mesh.addPrism(outline: square(keepHalf), bottom: plinthHeight, top: keepHeight)
			for y in [keepHeight * 0.4, keepHeight - 0.0006] {
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

		// A bartizan on each corner: corbelled out on a cone, its wall up to the parapet's, with
		// merlons round its outer side.
		let corners: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
		add(.stone) { mesh in
			for sign in corners {
				let center = SIMD3(sign.x * keepHalf, 0, sign.y * keepHalf)
				let base = keepHeight - 0.006
				mesh.addFrustum(sides: 10, bottomRadius: 0.0004, topRadius: bartizanRadius, bottom: base - bartizanCorbel, top: base, center: center)
				mesh.addFrustum(sides: 10, bottomRadius: bartizanRadius, topRadius: bartizanRadius, bottom: base, top: parapetTop, center: center)
				let outward = atan2(sign.y, sign.x)
				for index in 0..<3 {
					let angle = outward + Float(index - 1) * .pi / 3
					let spot = center + SIMD3(cos(angle), 0, sin(angle)) * (bartizanRadius - 0.0004)
					mesh.addPrism(outline: square(0.00045), bottom: parapetTop, top: parapetTop + merlonHeight, yaw: -angle, center: spot)
				}
			}
		}

		// Arrow slits up each face, and the doorway's shadow behind the door.
		add(.opening) { mesh in
			for side in 0..<4 {
				for (along, low) in [(-0.0032, 0.012), (0.0032, 0.022), (0, 0.03)] as [(Float, Float)] where !(side == 0 && low < 0.015) {
					let slit = onSide(side, along: along, width: 0.0005, depth: 0.0002, out: keepHalf)
					mesh.addPrism(outline: slit.outline, bottom: low, top: low + 0.0028, yaw: slit.yaw)
				}
			}
			let doorway = onSide(0, along: 0, width: 0.0034, depth: 0.0002, out: keepHalf + 0.0001)
			mesh.addPrism(outline: doorway.outline, bottom: plinthHeight, top: plinthHeight + 0.0062, yaw: doorway.yaw)
		}

		// The door in front, set into its doorway, and the banner pole.
		let pole = SIMD3(-keepHalf, 0, -keepHalf)
		add(.wood) { mesh in
			let door = onSide(0, along: 0, width: 0.0026, depth: 0.0002, out: keepHalf + 0.0002)
			mesh.addPrism(outline: door.outline, bottom: plinthHeight, top: plinthHeight + 0.0054, yaw: door.yaw)
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
}
