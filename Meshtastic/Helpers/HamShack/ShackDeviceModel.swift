//
//  ShackDeviceModel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd

/// The rough shape a node's radio takes in the shack. One mesh per shape, colored per node.
enum ShackDeviceArchetype: CaseIterable, Sendable {
	/// A phone-sized case with a screen: T-Echo, T-Deck, ThinkNode, trackers.
	case handheld
	/// A bare dev board on a stand: T-Beam, Heltec V3, RAK WisBlock, XIAO.
	case board
	/// A weatherproof box with a tall antenna: routers, repeaters, solar and base stations.
	case enclosure
	/// Anything the hardware name doesn't tell us about.
	case generic

	private static let enclosureNames = ["STATION", "SOLAR", "TOWER", "HUB", "MUZIBASE", "RAK6421", "METEOR"]
	private static let handheldNames = [
		"TECHO", "TDECK", "THINKNODE", "TRACKER", "T1000", "WISMESHTAG", "WISMESHTAP", "POCKET",
		"TWATCH", "PAGER", "CARD", "NANOG", "INDICATOR", "CROWPANEL", "EPAPER", "PAPER"
	]
	private static let boardNames = [
		"TLORA", "HELTEC", "TBEAM", "RAK", "XIAO", "DIY", "PICO", "PROMICRO", "LORA", "M5STACK",
		"CANARY", "NRF52", "WIO", "ESP32", "STACK", "BANDIT"
	]

	/// Infrastructure roles stand as enclosures whatever the hardware; otherwise the hardware
	/// model's name decides. Names are matched without case, underscores or dashes, so both the
	/// catalog's "T_ECHO" and the protobuf's "TECHO" work.
	init(hwModel: String?, role: DeviceRoles?) {
		if role?.isInfrastructure == true {
			self = .enclosure
			return
		}
		let name = (hwModel ?? "").uppercased().filter { $0 != "_" && $0 != "-" && $0 != " " }
		if Self.enclosureNames.contains(where: name.contains) {
			self = .enclosure
		} else if Self.handheldNames.contains(where: name.contains) {
			self = .handheld
		} else if Self.boardNames.contains(where: name.contains) {
			self = .board
		} else {
			self = .generic
		}
	}

	/// Where the screen is, in the device's space, and its size; the short name is drawn on it.
	var screen: (center: SIMD3<Float>, size: SIMD2<Float>) {
		switch self {
		case .handheld: (SIMD3(0, 0.088, 0.0151), SIMD2(0.058, 0.05))
		case .board: (SIMD3(0.012, 0.047, 0.0041), SIMD2(0.04, 0.024))
		case .enclosure: (SIMD3(0, 0.1, 0.0336), SIMD2(0.07, 0.026))
		case .generic: (SIMD3(0, 0.05, 0.0236), SIMD2(0.062, 0.03))
		}
	}

	/// How tall the device stands, antenna included.
	var height: Float {
		switch self {
		case .handheld: 0.2
		case .board: 0.195
		case .enclosure: 0.25
		case .generic: 0.18
		}
	}

	/// The device's parts, standing on the origin and facing +Z.
	var geometry: ShackMeshGeometry {
		var mesh = ShackMeshGeometry()
		let body = ShackMeshGeometry.Material.body, screenPart = ShackMeshGeometry.Material.screen, dark = ShackMeshGeometry.Material.dark
		let screen = self.screen
		switch self {
		case .handheld:
			mesh.addBox(center: [0, 0.065, 0], size: [0.075, 0.13, 0.028], material: body)
			mesh.addCylinder(base: [0.025, 0.13, -0.004], radius: 0.0055, height: 0.07, material: dark)
		case .board:
			mesh.addBox(center: [0, 0.006, 0], size: [0.1, 0.012, 0.05], material: dark)
			mesh.addBox(center: [0, 0.0445, 0], size: [0.1, 0.065, 0.006], material: body)
			mesh.addCylinder(base: [-0.038, 0.077, 0], radius: 0.004, height: 0.118, material: dark)
		case .enclosure:
			mesh.addBox(center: [0, 0.065, 0], size: [0.12, 0.13, 0.065], material: body)
			mesh.addBox(center: [0, 0.1225, 0], size: [0.124, 0.015, 0.069], material: dark)
			mesh.addCylinder(base: [0.035, 0.13, 0], radius: 0.008, height: 0.12, material: dark)
		case .generic:
			mesh.addBox(center: [0, 0.04, 0], size: [0.09, 0.08, 0.045], material: body)
			mesh.addCylinder(base: [0.03, 0.08, 0], radius: 0.005, height: 0.1, material: dark)
		}
		mesh.addBox(center: screen.center - [0, 0, 0.001], size: [screen.size.x, screen.size.y, 0.002], material: screenPart)
		return mesh
	}
}

/// Triangles for the shack's own meshes, grouped by material, kept free of RealityKit so they
/// can be checked in tests. Triangles wind counterclockwise seen from the side their normals face.
struct ShackMeshGeometry {
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

	/// An upright cylinder standing on `base`, with both ends capped.
	mutating func addCylinder(base: SIMD3<Float>, radius: Float, height: Float, material: Material, segments: Int = 12) {
		var part = parts[material] ?? Part()
		let ring = (0..<segments).map { i -> SIMD3<Float> in
			let angle = Float(i) / Float(segments) * 2 * .pi
			return SIMD3(cos(angle), 0, sin(angle))
		}
		let top = base + [0, height, 0]
		// Sides: a bottom and top vertex per segment, normals pointing out.
		let sideStart = UInt32(part.positions.count)
		for (i, out) in ring.enumerated() {
			part.positions += [base + out * radius, top + out * radius]
			part.normals += [out, out]
			part.uvs += [SIMD2(Float(i) / Float(segments), 0), SIMD2(Float(i) / Float(segments), 1)]
		}
		for i in 0..<UInt32(segments) {
			let next = (i + 1) % UInt32(segments)
			let bottom = sideStart + i * 2, upper = bottom + 1
			let nextBottom = sideStart + next * 2, nextUpper = nextBottom + 1
			part.indices += [bottom, upper, nextUpper, bottom, nextUpper, nextBottom]
		}
		// Caps: a fan around the center of each end.
		for (center, normal) in [(top, SIMD3<Float>(0, 1, 0)), (base, SIMD3<Float>(0, -1, 0))] {
			let middle = UInt32(part.positions.count)
			part.positions.append(center)
			part.normals.append(normal)
			part.uvs.append(SIMD2(0.5, 0.5))
			for out in ring {
				part.positions.append(center + out * radius)
				part.normals.append(normal)
				part.uvs.append(SIMD2(out.x, out.z) / 2 + 0.5)
			}
			for i in 0..<UInt32(segments) {
				let this = middle + 1 + i, next = middle + 1 + (i + 1) % UInt32(segments)
				part.indices += normal.y > 0 ? [middle, next, this] : [middle, this, next]
			}
		}
		parts[material] = part
	}

	/// The rack's cells for one page: a shallow box per cell standing out from the panel, each
	/// colored from its own texel of a `columns` × `rows` texture (row 0 at the top).
	static func rackCells(grid: ShackRackGrid, fill: Float = 0.8, depth: Float = 0.025) -> ShackMeshGeometry {
		var mesh = ShackMeshGeometry()
		let side = grid.pitch * fill
		for index in 0..<grid.perPage {
			let center = grid.center(ofCellOnPage: index)
			mesh.addBox(center: SIMD3(center.x, center.y, depth / 2), size: SIMD3(side, side, depth), material: .body, uv: rackTexel(index, grid: grid))
		}
		return mesh
	}

	/// The texture coordinate of a cell's texel. RealityKit samples with v = 0 at the bottom.
	static func rackTexel(_ index: Int, grid: ShackRackGrid) -> SIMD2<Float> {
		let column = index % grid.columns, row = index / grid.columns
		return SIMD2((Float(column) + 0.5) / Float(grid.columns), 1 - (Float(row) + 0.5) / Float(grid.rows))
	}
}
