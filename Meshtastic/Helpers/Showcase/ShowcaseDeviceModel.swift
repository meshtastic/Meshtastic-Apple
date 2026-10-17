//
//  ShowcaseDeviceModel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd

/// Triangles for the showcase's own meshes, grouped by material, kept free of RealityKit so they
/// can be checked in tests. Triangles wind counterclockwise seen from the side their normals face.
struct ShowcaseMeshGeometry {
	enum Material: Int, CaseIterable {
		/// The node's color.
		case body
		case screen
		/// Antennas, stands and lids.
		case dark
	}

	struct Part {
		var positions: [SIMD3<Float>] = []
		var normals: [SIMD3<Float>] = []
		var uvs: [SIMD2<Float>] = []
		var indices: [UInt32] = []
	}

	private struct BoxFace {
		let normal: SIMD3<Float>
		let u: SIMD3<Float>
		let v: SIMD3<Float>
	}

	private(set) var parts: [Material: Part] = [:]

	var triangleCount: Int { parts.values.reduce(0) { $0 + $1.indices.count / 3 } }

	/// A box. `uv`, when given, is used for every corner, so a texture can color the whole box
	/// from one texel; otherwise each face spans the texture.
	mutating func addBox(center: SIMD3<Float>, size: SIMD3<Float>, material: Material, uv: SIMD2<Float>? = nil) {
		let half = size / 2
		// Each face's two in-plane axes, ordered so that u × v is the face's normal.
		let faces: [BoxFace] = [
			BoxFace(normal: [1, 0, 0], u: [0, 1, 0], v: [0, 0, 1]),
			BoxFace(normal: [-1, 0, 0], u: [0, 0, 1], v: [0, 1, 0]),
			BoxFace(normal: [0, 1, 0], u: [0, 0, 1], v: [1, 0, 0]),
			BoxFace(normal: [0, -1, 0], u: [1, 0, 0], v: [0, 0, 1]),
			BoxFace(normal: [0, 0, 1], u: [1, 0, 0], v: [0, 1, 0]),
			BoxFace(normal: [0, 0, -1], u: [0, 1, 0], v: [1, 0, 0])
		]
		var part = parts[material] ?? Part()
		for face in faces {
			let first = UInt32(part.positions.count)
			let corners: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
			for corner in corners {
				part.positions.append(center + half * (face.normal + face.u * corner.x + face.v * corner.y))
				part.normals.append(face.normal)
				part.uvs.append(uv ?? (corner + 1) / 2)
			}
			part.indices += [first, first + 1, first + 2, first, first + 2, first + 3]
		}
		parts[material] = part
	}

	/// The rack's cells for one page: a shallow box per cell standing out from the panel, each
	/// colored from its own texel of a `columns` × `rows` texture (row 0 at the top).
	static func rackCells(grid: ShowcaseRackGrid, fill: Float = 0.8, depth: Float = 0.025) -> ShowcaseMeshGeometry {
		var mesh = ShowcaseMeshGeometry()
		let side = grid.pitch * fill
		for index in 0..<grid.perPage {
			let center = grid.center(ofCellOnPage: index)
			mesh.addBox(center: SIMD3(center.x, center.y, depth / 2), size: SIMD3(side, side, depth), material: .body, uv: rackTexel(index, grid: grid))
		}
		return mesh
	}

	/// The texture coordinate of a cell's texel. RealityKit samples with v = 0 at the bottom.
	static func rackTexel(_ index: Int, grid: ShowcaseRackGrid) -> SIMD2<Float> {
		let column = index % grid.columns, row = index / grid.columns
		return SIMD2((Float(column) + 0.5) / Float(grid.columns), 1 - (Float(row) + 0.5) / Float(grid.rows))
	}
}
