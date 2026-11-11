//
//  SpatialRooftopMesh.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import Foundation
import simd

/// What the cinema's city rooftop puts on the spatial map, on the roof of the building chosen for
/// it, as the fire lookout and the castle tower stand on their summit: a wooden water tower on
/// braced steel legs, and beside it a mast with a Yagi at the top. Small, like a marker, so it
/// reads on a roof among the other buildings; it stands from its base at y = 0, set on the roof.
enum SpatialRooftop {
	/// The parts drawn in their own material.
	enum Part: CaseIterable {
		/// The tank's staves and its platform.
		case staves
		/// The tank's conical roof.
		case roof
		/// The legs, braces, mast and the Yagi.
		case steel
	}

	/// The water tower, a little left of the middle, and the mast to its right; their front is +z,
	/// turned to the cinema's heading like the lookout's.
	static let tankCenter = SIMD2<Float>(-0.0022, 0)
	static let tankRadius: Float = 0.0030
	static let legHeight: Float = 0.0055
	static let tankHeight: Float = 0.0060
	static let roofHeight: Float = 0.0024
	static let mastCenter = SIMD2<Float>(0.0042, -0.0008)
	static let mastHeight: Float = 0.0165
	static let boomLength: Float = 0.0070
	private static let builtHeight = max(legHeight + tankHeight + roofHeight, mastHeight + 0.0004)
	/// The sizes here are drawn small, and on a roof among towers that reads as a speck even zoomed
	/// all the way in, so the whole water tower and mast are scaled up by this.
	static let scale: Float = 3
	/// From the roof to the top of the mast.
	static var height: Float { builtHeight * scale }
	static let triangleBudget = 1_200

	static func geometry() -> [Part: SpatialMeshData] {
		var parts: [Part: SpatialMeshData] = [:]
		for part in Part.allCases { parts[part] = SpatialMeshData() }
		let tank = SIMD3(tankCenter.x, 0, tankCenter.y)
		let tankBottom = legHeight
		let tankTop = legHeight + tankHeight

		parts[.staves]?.addFrustum(sides: 16, bottomRadius: tankRadius * 1.08, topRadius: tankRadius * 1.08, bottom: tankBottom - 0.0004, top: tankBottom, center: tank)
		parts[.staves]?.addFrustum(sides: 16, bottomRadius: tankRadius, topRadius: tankRadius, bottom: tankBottom, top: tankTop, center: tank)
		parts[.roof]?.addFrustum(sides: 16, bottomRadius: tankRadius * 1.06, topRadius: 0, bottom: tankTop, top: tankTop + roofHeight, center: tank)

		// Four legs leaning in to the tank's platform, braced in an X on each side.
		var steel = SpatialMeshData()
		let feet = (0..<4).map { i -> SIMD3<Float> in
			let angle = Float.pi / 4 + Float(i) * .pi / 2
			return tank + SIMD3(cos(angle), 0, sin(angle)) * tankRadius * 1.1
		}
		let tops = (0..<4).map { i -> SIMD3<Float> in
			let angle = Float.pi / 4 + Float(i) * .pi / 2
			return tank + SIMD3(cos(angle) * tankRadius * 0.8, tankBottom - 0.0004, sin(angle) * tankRadius * 0.8)
		}
		for i in 0..<4 {
			steel.addStrut(from: feet[i], to: tops[i], width: 0.0005)
			let j = (i + 1) % 4
			let lowI = feet[i] + (tops[i] - feet[i]) * 0.1, highI = feet[i] + (tops[i] - feet[i]) * 0.85
			let lowJ = feet[j] + (tops[j] - feet[j]) * 0.1, highJ = feet[j] + (tops[j] - feet[j]) * 0.85
			steel.addStrut(from: lowI, to: highJ, width: 0.00022)
			steel.addStrut(from: lowJ, to: highI, width: 0.00022)
		}

		// The mast on its ballasted foot, and the Yagi's boom along the front with its elements across.
		let mast = SIMD3(mastCenter.x, 0, mastCenter.y)
		steel.addPrism(outline: [[-0.0012, -0.0012], [0.0012, -0.0012], [0.0012, 0.0012], [-0.0012, 0.0012]], bottom: 0, top: 0.0006, center: mast)
		steel.addStrut(from: mast, to: mast + SIMD3(0, mastHeight + 0.0004, 0), width: 0.00045)
		let boomY = mastHeight
		let boomBack = mast + SIMD3(0, boomY, -boomLength * 0.3)
		let boomFront = mast + SIMD3(0, boomY, boomLength * 0.7)
		steel.addStrut(from: boomBack, to: boomFront, width: 0.00028)
		let elements: [Float] = [0.0034, 0.0031, 0.0029, 0.0028, 0.0027]
		for (index, length) in elements.enumerated() {
			let point = boomBack + (boomFront - boomBack) * ((Float(index) + 0.5) / Float(elements.count))
			steel.addStrut(from: point - SIMD3(length / 2, 0, 0), to: point + SIMD3(length / 2, 0, 0), width: 0.00016)
		}
		parts[.steel] = steel
		for part in Part.allCases {
			if let scaled = parts[part]?.positions.map({ $0 * scale }) { parts[part]?.positions = scaled }
		}
		return parts
	}
}

extension SpatialRoofs {
	/// How high something set on the roof at `point` stands: on top of the highest roof drawn there,
	/// or on the ground at `ground` where no building drawn covers it, as when the Buildings option
	/// is off.
	func standHeight(at point: SIMD2<Float>, ground: Float) -> Float {
		top(at: point).map { max($0, ground) } ?? ground
	}
}
