//
//  SpatialStationMesh.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import Foundation
import simd

/// The space station the cinema's space station room is in, drawn on the spatial map floating high
/// over the middle of the mesh while that room is chosen. Not where the real station is, but laid
/// out like it, at about its real proportions: the integrated truss with its rotary joints and
/// payload carriers, Canadarm2 on its mobile base, eight solar wings in cell panels with the newer
/// roll-out arrays over six of them, the big radiators hanging down and aft inboard and the smaller
/// ones by the wings, and the modules from a docked Crew Dragon at the front, through Harmony with
/// Columbus and Kibo, Destiny under the truss, Unity with Quest and Tranquility, the cupola under
/// it, to Zarya, Zvezda with its blue wings, Poisk with a Soyuz, Nauka, and a Progress at the back.
/// Built in room meters, about 12 cm across the truss at the whole mesh, and growing as the map
/// zooms in.
enum SpatialStation {
	/// The parts drawn in their own material.
	enum Part: CaseIterable {
		/// The truss, the wings' masts and their boxes.
		case truss
		/// The main solar wings' blankets.
		case solar
		/// The roll-out arrays, and the Russian segment's and the docked ships' wings.
		case rollout
		/// The radiators.
		case radiator
		/// The pressurized modules and the docked ships.
		case module
		/// The cupola's windows.
		case window
		/// Canadarm2 and Kibo's small arm.
		case arm
		/// Payload carriers, Kibo's outdoor platform and Dragon's trunk.
		case dark
		/// The Meshtastic mark on the plate over the truss's middle.
		case logo
	}

	/// The truss, along x.
	static let trussLength: Float = 0.12
	static let trussWidth: Float = 0.0034
	/// The solar wings: pairs out along z from the truss at these points along it, each wing this
	/// wide along the truss and this long out from it.
	static let wingStations: [Float] = [-0.0535, -0.0415, 0.0415, 0.0535]
	static let wingWidth: Float = 0.0105
	static let wingLength: Float = 0.034
	static let wingGap: Float = 0.003
	/// The modules hang this far under the truss's middle.
	static let moduleDrop: Float = 0.0055
	/// The US modules' radius; the others are sized from it.
	static let moduleRadius: Float = 0.0023
	/// The rotary joints that turn the outboard truss and its wings.
	static let jointStation: Float = 0.034
	/// How long one turn round the mesh takes, and how far out from its middle the turn is, as a
	/// share of the map's radius.
	static let orbitPeriod: TimeInterval = 240
	static let orbitShare: Float = 0.3
	/// How far over the highest ground or roof under the map it floats, in room meters, and how
	/// much room it needs above and below its middle.
	static let clearance: Float = 0.1
	static let halfHeight: Float = 0.024
	static let triangleBudget = 9_000
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

	/// The whole station centered on the truss's middle: the truss along x, forward along +z, the
	/// cupola down.
	static func geometry() -> [Part: SpatialMeshData] {
		var parts: [Part: SpatialMeshData] = [:]
		for part in Part.allCases { parts[part] = SpatialMeshData() }
		func add(_ part: Part, _ build: (inout SpatialMeshData) -> Void) {
			build(&parts[part, default: SpatialMeshData()])
		}
		let y = -moduleDrop
		let r = moduleRadius
		let tw = trussWidth / 2
		let x: SIMD3<Float> = [1, 0, 0], up: SIMD3<Float> = [0, 1, 0], z: SIMD3<Float> = [0, 0, 1]

		add(.truss) { mesh in
			// The beam, open framework: four longerons with a lattice along three faces.
			let half = trussLength / 2
			mesh.addBox(center: .zero, x * half, up * tw * 0.55, z * tw * 0.55)
			for (py, pz) in [(tw, tw), (tw, -tw), (-tw, tw), (-tw, -tw)] {
				mesh.addStrut(from: [-half, py, pz], to: [half, py, pz], width: 0.0004)
			}
			let bays = 24
			for bay in 0..<bays {
				let x0 = -half + trussLength * Float(bay) / Float(bays)
				let x1 = -half + trussLength * Float(bay + 1) / Float(bays)
				mesh.addStrut(from: [x0, tw, tw], to: [x1, -tw, tw], width: 0.00025)
				mesh.addStrut(from: [x0, tw, -tw], to: [x1, -tw, -tw], width: 0.00025)
				mesh.addStrut(from: [x0, tw, tw], to: [x1, tw, -tw], width: 0.00025)
			}
			// The center segment over Destiny, and its struts down to the lab.
			mesh.addBox(center: .zero, x * 0.0055, up * tw * 1.15, z * tw * 1.15)
			for side: Float in [-1, 1] {
				mesh.addStrut(from: [side * 0.0014, -tw, 0], to: [side * 0.0014, y + r * 0.9, 0], width: 0.0005)
			}
			// The rotary joints, turning the outboard truss and its wings.
			for side: Float in [-1, 1] {
				mesh.addTube(from: [side * (jointStation - 0.0018), 0, 0], to: [side * (jointStation + 0.0018), 0, 0], radius: tw * 1.45, sides: 16)
			}
			// Each wing's mast out along z, the box at its root, and the blanket boxes at its ends.
			for wx in wingStations {
				mesh.addBox(center: [wx, 0, 0], x * 0.002, up * tw * 1.4, z * tw * 1.4)
				for sign: Float in [-1, 1] {
					mesh.addStrut(from: [wx, 0, sign * tw], to: [wx, 0, sign * (wingGap + wingLength)], width: 0.0005)
					for end in [wingGap, wingGap + wingLength] {
						mesh.addBox(center: [wx, 0, sign * end], x * wingWidth / 2, up * 0.0003, z * 0.0004)
					}
				}
			}
			// The plate over the middle the Meshtastic mark stands on.
			mesh.addBox(center: [0, tw * 1.15 + 0.00015, 0], x * logoWidth * 0.55, up * 0.00015, z * logoWidth * 0.31)
			// Canadarm2's mobile base on the truss's front face.
			mesh.addBox(center: [0.0108, tw + 0.0004, tw * 0.4], x * 0.0022, up * 0.0004, z * 0.0022)
		}

		// Eight wings, each two blankets either side of its mast, in panels of cells.
		add(.solar) { mesh in
			let panels = 10, gap: Float = 0.00025
			let panelLength = (wingLength - gap * Float(panels + 1)) / Float(panels)
			let blanket = wingWidth / 2 - 0.0005
			for wx in wingStations {
				for sign: Float in [-1, 1] {
					for side: Float in [-1, 1] {
						let bx = wx + side * (wingWidth / 4 + 0.0002)
						for panel in 0..<panels {
							let along = wingGap + gap + (panelLength + gap) * Float(panel) + panelLength / 2
							mesh.addBox(center: [bx, 0, sign * along], x * blanket / 2, up * 0.0001, z * panelLength / 2)
						}
					}
				}
			}
		}

		add(.rollout) { mesh in
			// The roll-out arrays, canted over the outer half of six of the wings.
			for (wx, sign) in [(-0.0535, Float(1)), (-0.0535, -1), (0.0415, 1), (0.0415, -1), (0.0535, 1), (0.0535, -1)] as [(Float, Float)] {
				let cant: Float = 0.2
				let across = simd_normalize(SIMD3<Float>(cos(cant), sin(cant), 0))
				let normal = simd_cross(z, across)
				let panels = 6, gap: Float = 0.0002
				let length: Float = 0.02, start = wingGap + 0.0125
				let panelLength = (length - gap * Float(panels - 1)) / Float(panels)
				for panel in 0..<panels {
					let along = start + (panelLength + gap) * Float(panel) + panelLength / 2
					mesh.addBox(center: [wx, 0.0011, sign * along], across * 0.0031, normal * 0.00008, z * panelLength / 2)
				}
				mesh.addStrut(from: [wx, 0, sign * start], to: [wx, 0.0011, sign * (start + 0.001)], width: 0.0003)
			}
			// Zvezda's wings, out either side of its wide end.
			for side: Float in [-1, 1] {
				mesh.addBox(center: [side * 0.0088, y, -0.0368], x * 0.0058, up * 0.0001, z * 0.0016)
			}
			// The Soyuz's wings on Poisk, and the Progress's at the back.
			for side: Float in [-1, 1] {
				mesh.addBox(center: [side * 0.0037, 0.0066, -0.0276], x * 0.0023, z * 0.0001, up * 0.0006)
				mesh.addBox(center: [side * 0.0036, y, -0.0478], x * 0.0022, up * 0.0001, z * 0.0006)
			}
		}

		add(.radiator) { mesh in
			// The main radiators, three each side of the middle, hanging down and aft in eight panels.
			let down = simd_normalize(SIMD3<Float>(0, -1, -0.9))
			let face = simd_cross(down, x)
			let panels = 8, panelLength: Float = 0.0023, gap: Float = 0.00015
			for side: Float in [-1, 1] {
				for strip in 0..<3 {
					let sx = side * (0.0127 + Float(strip) * 0.0037)
					for panel in 0..<panels {
						let center = SIMD3<Float>(sx, -tw, 0) + down * (0.0006 + (panelLength + gap) * Float(panel) + panelLength / 2)
						mesh.addBox(center: center, x * 0.0016, face * 0.0001, down * panelLength / 2)
					}
				}
			}
			// The smaller radiators by the wings, hanging straight down.
			for wx: Float in [-0.0475, 0.0475] {
				for panel in 0..<6 {
					mesh.addBox(center: [wx, -tw - 0.0006 - 0.0021 * (Float(panel) + 0.5), 0], x * 0.0001, up * 0.00095, z * 0.0016)
				}
			}
		}

		add(.module) { mesh in
			func module(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ radius: Float) {
				mesh.addTube(from: a, to: b, radius: radius)
				// The berthing rings at each end, a little proud of the hull.
				let d = simd_normalize(b - a) * 0.0003
				mesh.addTube(from: a, to: a + d, radius: radius * 1.06)
				mesh.addTube(from: b - d, to: b, radius: radius * 1.06)
			}
			let kiboZ: Float = 0.009, unityZ: Float = -0.0082
			module([0, y, -0.0047], [0, y, 0.0047], r)                      // Destiny
			module([0, y, 0.0051], [0, y, 0.0128], r)                       // Harmony
			module([0.0024, y, kiboZ], [0.0098, y, kiboZ], r * 0.98)        // Columbus
			mesh.addTube(from: [0.0098, y, kiboZ], to: [0.0105, y, kiboZ], radius: r * 0.98, endRadius: r * 0.55)
			module([-0.0024, y, kiboZ], [-0.0146, y, kiboZ], r)             // Kibo
			module([-0.0075, y + r, kiboZ], [-0.0075, y + r + 0.0045, kiboZ], r * 0.9) // Kibo's storage
			module([0, y, unityZ + 0.0031], [0, y, unityZ - 0.0031], r)     // Unity
			module([0.0024, y, unityZ], [0.0058, y, unityZ], r * 0.9)       // Quest
			mesh.addTube(from: [0.0058, y, unityZ], to: [0.0084, y, unityZ], radius: r * 0.65)
			module([-0.0024, y, unityZ], [-0.0096, y, unityZ], r)           // Tranquility
			module([-0.0062, y, unityZ + r], [-0.0062, y, unityZ + r + 0.0062], r * 0.98) // the storage module
			mesh.addTube(from: [-0.0072, y, unityZ - r], to: [-0.0072, y, unityZ - r - 0.002], radius: 0.0015) // BEAM
			// The cupola under Tranquility, its seven sides tapering down to the round window.
			mesh.addFrustum(sides: 7, bottomRadius: 0.0012, topRadius: 0.0017, bottom: y - r - 0.0017, top: y - r + 0.0003, center: [-0.0062, 0, unityZ])
			// The adapters fore and aft, and the Crew Dragon docked at the front.
			mesh.addTube(from: [0, y, 0.0128], to: [0, y, 0.0150], radius: 0.0013, endRadius: 0.0009)
			mesh.addTube(from: [0, y, 0.0150], to: [0, y, 0.0185], radius: 0.0009, endRadius: 0.0021, sides: 18)
			mesh.addTube(from: [0, y, -0.0112], to: [0, y, -0.0130], radius: 0.0014)
			// Zarya, tapering aft, with Rassvet under it.
			module([0, y, -0.0130], [0, y, -0.0230], 0.00225)
			mesh.addTube(from: [0, y, -0.0230], to: [0, y, -0.0262], radius: 0.00225, endRadius: 0.0014)
			module([0, y - 0.00225, -0.0180], [0, y - 0.00225 - 0.0066, -0.0180], 0.0013)
			// Zvezda: its ball of a forward node, the narrow and wide halves, the cone aft.
			mesh.addBall(center: [0, y, -0.0276], radius: 0.0015)
			mesh.addTube(from: [0, y, -0.0289], to: [0, y, -0.0340], radius: 0.0016)
			mesh.addTube(from: [0, y, -0.0340], to: [0, y, -0.0344], radius: 0.0016, endRadius: 0.0023)
			mesh.addTube(from: [0, y, -0.0344], to: [0, y, -0.0398], radius: 0.0023)
			mesh.addTube(from: [0, y, -0.0398], to: [0, y, -0.0418], radius: 0.0023, endRadius: 0.0010)
			// Poisk up from the node, with a Soyuz on it: orbital module, descent module, service module.
			mesh.addTube(from: [0, y + 0.0014, -0.0276], to: [0, 0.0001, -0.0276], radius: 0.0013)
			mesh.addBall(center: [0, 0.0014, -0.0276], radius: 0.0012)
			mesh.addTube(from: [0, 0.0025, -0.0276], to: [0, 0.0045, -0.0276], radius: 0.0008, endRadius: 0.0012)
			mesh.addTube(from: [0, 0.0045, -0.0276], to: [0, 0.0074, -0.0276], radius: 0.0012)
			// Nauka down from the node, with Prichal's ball at its end.
			module([0, y - 0.0014, -0.0276], [0, y - 0.0014 - 0.0125, -0.0276], 0.0021)
			mesh.addBall(center: [0, y - 0.0014 - 0.0125 - 0.0011, -0.0276], radius: 0.0011)
			// The Progress at the back: cargo, tanks, service module.
			mesh.addTube(from: [0, y, -0.0418], to: [0, y, -0.0450], radius: 0.0012)
			mesh.addTube(from: [0, y, -0.0450], to: [0, y, -0.0462], radius: 0.0010)
			mesh.addTube(from: [0, y, -0.0462], to: [0, y, -0.0490], radius: 0.0013)
		}

		add(.window) { mesh in
			// The cupola's round top window, looking down, and a window in each of its sides.
			let cy = y - r - 0.0017
			mesh.addFrustum(sides: 14, bottomRadius: 0.00085, topRadius: 0.00085, bottom: cy - 0.00006, top: cy, center: [-0.0062, 0, -0.0082])
			for i in 0..<7 {
				let angle = (Float(i) + 0.5) * 2 * .pi / 7
				let mid = SIMD3<Float>(cos(angle), 0, sin(angle))
				let slope = simd_normalize(SIMD3<Float>(0, 1, 0) * 0.0005 + mid * 0.002)
				let center = SIMD3<Float>(-0.0062, cy + 0.001, -0.0082) + mid * 0.00128
				let along = simd_normalize(simd_cross(up, mid))
				let outward = simd_normalize(simd_cross(along, slope))
				mesh.addBox(center: center + outward * 0.00004, along * 0.0004, outward * 0.00003, simd_normalize(slope - outward * simd_dot(slope, outward)) * 0.00055)
			}
		}

		add(.arm) { mesh in
			// Canadarm2 reaching out from its base: two booms between its joints.
			let shoulder = SIMD3<Float>(0.0108, tw + 0.0012, tw * 0.4)
			let elbow = SIMD3<Float>(0.0143, 0.0085, 0.0062)
			let wrist = SIMD3<Float>(0.0173, 0.0034, 0.0128)
			mesh.addTube(from: shoulder - up * 0.0004, to: shoulder + up * 0.0004, radius: 0.0005, sides: 10)
			mesh.addTube(from: shoulder, to: elbow, radius: 0.00028, sides: 8)
			mesh.addTube(from: elbow - x * 0.0004, to: elbow + x * 0.0004, radius: 0.0005, sides: 10)
			mesh.addTube(from: elbow, to: wrist, radius: 0.00028, sides: 8)
			mesh.addTube(from: wrist, to: wrist - up * 0.0012, radius: 0.0004, sides: 10)
			// Kibo's small arm, folded at the end of the lab.
			mesh.addTube(from: [-0.0140, y + r, 0.0090], to: [-0.0160, y + r + 0.0018, 0.0075], radius: 0.00018, sides: 6)
			mesh.addTube(from: [-0.0160, y + r + 0.0018, 0.0075], to: [-0.0180, y + r + 0.0006, 0.0095], radius: 0.00016, sides: 6)
		}

		add(.dark) { mesh in
			// Payload carriers on the truss, and AMS-02 on top of the starboard side.
			for px: Float in [-0.027, 0.027] {
				for py: Float in [tw + 0.0006, -tw - 0.0006] {
					mesh.addBox(center: [px, py, 0], x * 0.002, up * 0.0006, z * 0.0021)
				}
			}
			mesh.addTube(from: [0.0305, tw, 0], to: [0.0305, tw + 0.0018, 0], radius: 0.0016, sides: 12)
			// Kibo's outdoor platform with its experiments.
			mesh.addBox(center: [-0.0178, y, 0.009], x * 0.0029, up * 0.0006, z * 0.0028)
			for (ex, ez) in [(-0.0166, 0.0080), (-0.0186, 0.0102), (-0.0192, 0.0078)] as [(Float, Float)] {
				mesh.addBox(center: [ex, y + 0.001, ez], x * 0.0006, up * 0.0004, z * 0.0005)
			}
			// Dragon's heat shield and trunk behind the capsule.
			mesh.addTube(from: [0, y, 0.0185], to: [0, y, 0.0189], radius: 0.0021, sides: 18)
			mesh.addTube(from: [0, y, 0.0189], to: [0, y, 0.0218], radius: 0.0020, sides: 18)
		}
		add(.logo) { mesh in
			// The Meshtastic mark, read from the front, standing proud of its plate: the slash and
			// the two legs of the peak, each a convex piece.
			let bottom = tw * 1.15 + 0.0003
			for piece in logoOutline {
				let outline = piece.map { SIMD2<Float>($0.x * logoWidth, -$0.y * logoWidth) }
				let middle = outline.reduce(.zero, +) / Float(outline.count)
				let ordered = outline.sorted { atan2($0.y - middle.y, $0.x - middle.x) < atan2($1.y - middle.y, $1.x - middle.x) }
				mesh.addPrism(outline: ordered, bottom: bottom, top: bottom + 0.00025)
			}
		}
		return parts
	}

	/// How wide the Meshtastic mark is on the plate over the truss's middle.
	static let logoWidth: Float = 0.014
	/// The Meshtastic mark from the app's logo artwork, a unit wide, centered, y up: the slash and
	/// the peak's two legs.
	static let logoOutline: [[SIMD2<Float>]] = [
		[[-0.4401, -0.2634], [-0.1085, 0.223], [-0.1684, 0.2638], [-0.5, -0.2225]],
		[[0.1556, 0.1526], [-0.1283, -0.2638], [-0.1882, -0.223], [0.1256, 0.2372], [0.1555, 0.253]],
		[[0.1555, 0.253], [0.1855, 0.2373], [0.5, -0.2222], [0.4402, -0.2631], [0.1556, 0.1526]]
	]
}

extension SpatialMeshData {
	/// A round tube from `a` to `b`, capped at both ends: a frustum built standing up and turned onto
	/// the line between them.
	mutating func addCylinder(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, sides: Int = 14) {
		addTube(from: a, to: b, radius: radius, sides: sides)
	}

	/// A capped tube from `a` to `b`, `radius` round at `a` and `endRadius` (the same when nil) at `b`.
	mutating func addTube(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, endRadius: Float? = nil, sides: Int = 14) {
		var piece = SpatialMeshData()
		let length = simd_distance(a, b)
		piece.addFrustum(sides: sides, bottomRadius: radius, topRadius: endRadius ?? radius, bottom: 0, top: length)
		let turn = simd_quatf(from: [0, 1, 0], to: simd_normalize(b - a))
		append(piece, transform: { a + turn.act($0) }, rotate: { turn.act($0) })
	}

	/// A box round `center` along three square-on half-extent vectors, so it can lie at any angle.
	mutating func addBox(center: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
		for (n, u, v) in [(a, b, c), (b, c, a), (c, a, b)] {
			for sign: Float in [-1, 1] {
				let mid = center + n * sign
				let low = mid - v
				let high = mid + v
				var quad: [SIMD3<Float>] = [low - u, low + u, high + u, high - u]
				if simd_dot(simd_cross(quad[1] - quad[0], quad[2] - quad[0]), n * sign) < 0 { quad.reverse() }
				let normal = simd_normalize(n * sign)
				let first = UInt32(positions.count)
				positions += quad
				normals += Array(repeating: normal, count: 4)
				indices += [first, first + 1, first + 2, first, first + 2, first + 3]
			}
		}
	}

	/// A ball, shaded round, in `rings` bands of `segments`.
	mutating func addBall(center: SIMD3<Float>, radius: Float, rings: Int = 7, segments: Int = 12) {
		func point(_ ring: Int, _ segment: Int) -> SIMD3<Float> {
			let polar = Float.pi * Float(ring) / Float(rings)
			let around = 2 * Float.pi * Float(segment) / Float(segments)
			return SIMD3(sin(polar) * cos(around), cos(polar), sin(polar) * sin(around))
		}
		for ring in 0..<rings {
			for segment in 0..<segments {
				let corners = [point(ring, segment), point(ring + 1, segment), point(ring + 1, segment + 1), point(ring, segment + 1)]
				for triangle in [[0, 1, 2], [0, 2, 3]] {
					var t = triangle.map { corners[$0] }
					// The poles' bands have a corner twice over; skip the triangle that collapses there.
					if simd_length(simd_cross(t[1] - t[0], t[2] - t[0])) < 1e-9 { continue }
					if simd_dot(simd_cross(t[1] - t[0], t[2] - t[0]), t[0] + t[1] + t[2]) < 0 { t.reverse() }
					let first = UInt32(positions.count)
					positions += t.map { center + $0 * radius }
					normals += t.map { simd_normalize($0) }
					indices += [first, first + 1, first + 2]
				}
			}
		}
	}

	/// Adds another mesh's triangles, moved and turned.
	private mutating func append(_ piece: SpatialMeshData, transform: (SIMD3<Float>) -> SIMD3<Float>, rotate: (SIMD3<Float>) -> SIMD3<Float>) {
		let first = UInt32(positions.count)
		positions += piece.positions.map(transform)
		normals += piece.normals.map(rotate)
		indices += piece.indices.map { $0 + first }
	}
}
