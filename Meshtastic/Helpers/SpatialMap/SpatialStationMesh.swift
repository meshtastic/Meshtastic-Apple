//
//  SpatialStationMesh.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import Foundation
import simd

/// The space station the cinema's space station room is in, drawn on the spatial map floating high
/// over the middle of the mesh while that room is chosen: the long truss with four pairs of solar
/// wings out at its ends and white radiators inboard of them, the pressurized modules strung across
/// the truss's middle with the Russian segment's own small wings behind, and the cupola on the
/// underside. Not where the real station is; just recognizable at a glance. Built in room meters,
/// about 12 cm across the truss at the whole mesh, and growing as the map zooms in.
enum SpatialStation {
	/// The parts drawn in their own material.
	enum Part: CaseIterable {
		/// The truss and the wings' masts.
		case truss
		/// The solar wings.
		case solar
		/// The radiators.
		case radiator
		/// The pressurized modules.
		case module
		/// The cupola's windows.
		case window
	}

	/// The truss, along x.
	static let trussLength: Float = 0.12
	static let trussWidth: Float = 0.0034
	/// The solar wings: pairs out along z from the truss at these points along it, each wing this
	/// wide along the truss and this long out from it.
	static let wingStations: [Float] = [-0.058, -0.045, 0.045, 0.058]
	static let wingWidth: Float = 0.0105
	static let wingLength: Float = 0.034
	static let wingGap: Float = 0.003
	/// The modules hang this far under the truss's middle.
	static let moduleDrop: Float = 0.0055
	static let moduleRadius: Float = 0.0021
	/// How long one turn round the mesh takes, and how far out from its middle the turn is, as a
	/// share of the map's radius.
	static let orbitPeriod: TimeInterval = 240
	static let orbitShare: Float = 0.3
	/// How far over the highest ground or roof under the map it floats, in room meters, and how
	/// much room it needs above and below its middle.
	static let clearance: Float = 0.1
	static let halfHeight: Float = 0.022
	static let triangleBudget = 2_000
	/// The most the station grows as the map zooms in, so it never fills the table.
	static let maximumGrowth: Float = 3

	/// How much bigger than at the whole mesh the station is drawn at `zoom`: as much bigger as
	/// the map, up to `maximumGrowth`, so it comes closer as you zoom in like the ground under it.
	static func growth(zoom: Double) -> Float {
		guard zoom.isFinite else { return 1 }
		return min(max(Float(zoom), 1), maximumGrowth)
	}

	/// How high the station's middle floats, in model units: `clearance` over the highest of the
	/// terrain and the roofs, and under `ceiling` (the top of the volume) where there is one,
	/// though never down into what it floats over. `counterScale` is model units per room meter.
	static func height(terrainTop: Float, roofTop: Float?, counterScale: Float, ceiling: Float? = nil) -> Float {
		let top = max(terrainTop, roofTop ?? -.infinity)
		let wanted = top + clearance * counterScale
		let lowest = top + halfHeight * counterScale
		guard let ceiling else { return wanted }
		return max(min(wanted, ceiling - halfHeight * counterScale), lowest)
	}

	/// The whole station centered on the origin, the truss along x and the modules along z, the
	/// cupola down.
	static func geometry() -> [Part: SpatialMeshData] {
		var parts: [Part: SpatialMeshData] = [:]
		for part in Part.allCases { parts[part] = SpatialMeshData() }
		func add(_ part: Part, _ build: (inout SpatialMeshData) -> Void) {
			build(&parts[part, default: SpatialMeshData()])
		}
		func box(_ mesh: inout SpatialMeshData, center: SIMD3<Float>, size: SIMD3<Float>) {
			let x = size.x / 2, z = size.z / 2
			mesh.addPrism(outline: [[-x, -z], [x, -z], [x, z], [-x, z]], bottom: center.y - size.y / 2, top: center.y + size.y / 2, center: [center.x, 0, center.z])
		}

		// The truss: a long square beam, with a lattice of struts along its faces so it reads as
		// open framework, and the wings' masts across it.
		add(.truss) { mesh in
			let half = trussLength / 2
			box(&mesh, center: .zero, size: [trussLength, trussWidth * 0.55, trussWidth * 0.55])
			let w = trussWidth / 2
			for (y, z) in [(w, w), (w, -w), (-w, w), (-w, -w)] {
				mesh.addStrut(from: [-half, y, z], to: [half, y, z], width: 0.0004)
			}
			let bays = 18
			for bay in 0..<bays {
				let x0 = -half + trussLength * Float(bay) / Float(bays)
				let x1 = -half + trussLength * Float(bay + 1) / Float(bays)
				mesh.addStrut(from: [x0, w, w], to: [x1, -w, w], width: 0.00025)
				mesh.addStrut(from: [x0, w, -w], to: [x1, -w, -w], width: 0.00025)
				mesh.addStrut(from: [x0, w, w], to: [x1, w, -w], width: 0.00025)
			}
			for x in wingStations {
				mesh.addStrut(from: [x, 0, -(wingLength + wingGap)], to: [x, 0, wingLength + wingGap], width: 0.0005)
				box(&mesh, center: [x, 0, 0], size: [0.004, trussWidth * 1.4, trussWidth * 1.4])
			}
		}

		// Four pairs of wings, each a long blanket either side of its mast.
		add(.solar) { mesh in
			for x in wingStations {
				for sign: Float in [-1, 1] {
					let middle = sign * (wingGap + wingLength / 2)
					for side: Float in [-1, 1] {
						box(&mesh, center: [x + side * (wingWidth / 4 + 0.0003), 0, middle], size: [wingWidth / 2 - 0.0005, 0.0002, wingLength])
					}
				}
			}
			// The Russian segment's small wings, behind the modules.
			for side: Float in [-1, 1] {
				box(&mesh, center: [side * 0.012, -moduleDrop, -0.034], size: [0.016, 0.0002, 0.0042])
			}
		}

		// The radiators inboard of the wings, hanging edge-on below the truss.
		add(.radiator) { mesh in
			for x: Float in [-0.026, -0.019, 0.019, 0.026] {
				box(&mesh, center: [x, -0.011, -0.002], size: [0.0055, 0.016, 0.0003])
			}
		}

		// The modules: a string across the truss's middle, front to back, with the lab modules
		// branching off the front node and the Russian segment behind.
		add(.module) { mesh in
			let y = -moduleDrop
			mesh.addCylinder(from: [0, y, -0.034], to: [0, y, 0.026], radius: moduleRadius)
			mesh.addCylinder(from: [-0.014, y, 0.022], to: [0.014, y, 0.022], radius: moduleRadius * 0.95)
			mesh.addCylinder(from: [0, y, 0.026], to: [0, y, 0.031], radius: moduleRadius * 0.75)
			// Node 3 off to the left of the middle node, with the cupola under it.
			mesh.addCylinder(from: [-0.011, y, 0.004], to: [0, y, 0.004], radius: moduleRadius * 0.9)
			mesh.addCylinder(from: [0, y + 0.0018, 0], to: [0, 0, 0], radius: moduleRadius * 0.7)
			mesh.addCylinder(from: [0, y, -0.034], to: [0, y, -0.041], radius: moduleRadius * 1.1)
			mesh.addFrustum(sides: 6, bottomRadius: 0.0012, topRadius: 0.0018, bottom: y - moduleRadius * 0.9 - 0.0016, top: y - moduleRadius * 0.9 + 0.0002, center: [-0.007, 0, 0.004], turn: .pi / 6)
		}
		add(.window) { mesh in
			mesh.addFrustum(sides: 6, bottomRadius: 0.0009, topRadius: 0.0011, bottom: -moduleDrop - moduleRadius * 0.9 - 0.0018, top: -moduleDrop - moduleRadius * 0.9 - 0.0015, center: [-0.007, 0, 0.004], turn: .pi / 6)
		}
		return parts
	}
}

extension SpatialMeshData {
	/// A round tube from `a` to `b`, capped at both ends: a frustum built standing up and turned onto
	/// the line between them.
	mutating func addCylinder(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, sides: Int = 14) {
		var piece = SpatialMeshData()
		let length = simd_distance(a, b)
		piece.addFrustum(sides: sides, bottomRadius: radius, topRadius: radius, bottom: 0, top: length)
		let turn = simd_quatf(from: [0, 1, 0], to: simd_normalize(b - a))
		let first = UInt32(positions.count)
		positions += piece.positions.map { a + turn.act($0) }
		normals += piece.normals.map { turn.act($0) }
		indices += piece.indices.map { $0 + first }
	}
}
