//
//  SpatialLighthouseMesh.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import Foundation
import simd

/// The lighthouse the cinema's lantern room is in, drawn on the spatial map at the headland chosen
/// for it, as the fire lookout is on its summit: a white tower tapering up from a stone plinth, a
/// door at its foot and small windows up it, a railed gallery at the top, and over that the lantern,
/// glazed all round and lit, under a red dome with a ventilator and a lightning rod. Taller than
/// the lookout and about as wide as its cab, and well inside the room the map keeps clear round
/// it, so it steps aside from a node on the same headland the same way.
enum SpatialLighthouse {
	/// The parts drawn in their own material.
	enum Part: CaseIterable {
		/// The tower's white walls.
		case tower
		/// The plinth it stands on.
		case stone
		/// The door and windows.
		case opening
		/// The gallery, the lantern's frame and the railing, painted dark.
		case iron
		/// The lantern's glass, with the lamp lit behind it.
		case glass
		/// The dome.
		case dome
		case metal
	}

	static let sides = 16
	/// The tower, from the top of the plinth to the gallery.
	static let plinthRadius: Float = 0.0064
	static let plinthHeight: Float = 0.0016
	static let baseRadius: Float = 0.0054
	static let topRadius: Float = 0.0036
	static let towerTop: Float = 0.032
	/// The gallery: a deck wider than the tower's top, on a corbel, with a railing.
	static let galleryRadius: Float = 0.0054
	static let galleryThickness: Float = 0.0006
	static let railHeight: Float = 0.0022
	/// The lantern: a low parapet, the glass, the cornice and the dome.
	static let lanternSides = 12
	static let lanternRadius: Float = 0.0032
	static let parapetHeight: Float = 0.0014
	static let glassHeight: Float = 0.0046
	static let corniceRadius: Float = 0.0039
	static let corniceHeight: Float = 0.0005
	static let domeRise: Float = 0.0028
	static let ventHeight: Float = 0.0012
	static let rodHeight: Float = 0.0026
	static let triangleBudget = 1_800

	static var galleryTop: Float { towerTop + galleryThickness }
	static var glassBottom: Float { galleryTop + parapetHeight }
	static var glassTop: Float { glassBottom + glassHeight }
	static var domeBottom: Float { glassTop + corniceHeight }
	static var domeTop: Float { domeBottom + domeRise }
	/// From the ground to the tip of the lightning rod, before it's scaled up.
	private static var builtHeight: Float { domeTop + ventHeight + rodHeight }
	/// The sizes here are drawn at about the lookout's height, but a tower that slender reads as
	/// tiny beside the lookout's wide cab, so the whole lighthouse is scaled up by this.
	static let scale: Float = 1.6
	/// From the ground to the tip of the lightning rod.
	static var height: Float { builtHeight * scale }

	/// Half the tower's width at height `y` above the plinth, narrowing up to the gallery.
	static func towerRadius(at y: Float) -> Float {
		baseRadius + (topRadius - baseRadius) * min(max((y - plinthHeight) / (towerTop - plinthHeight), 0), 1)
	}

	/// The whole lighthouse standing on y = 0, centered on the origin, its lantern's front toward +z.
	static func geometry() -> [Part: SpatialMeshData] {
		var parts: [Part: SpatialMeshData] = [:]
		for part in Part.allCases { parts[part] = SpatialMeshData() }
		func add(_ part: Part, _ build: (inout SpatialMeshData) -> Void) {
			build(&parts[part, default: SpatialMeshData()])
		}

		add(.stone) { $0.addFrustum(sides: sides, bottomRadius: plinthRadius, topRadius: plinthRadius * 0.95, bottom: 0, top: plinthHeight) }
		add(.tower) { $0.addFrustum(sides: sides, bottomRadius: baseRadius, topRadius: topRadius, bottom: plinthHeight, top: towerTop) }

		// The door at the foot, at the back, and a window above it on alternate sides up the tower,
		// each a dark panel just proud of the wall where it is.
		add(.opening) { mesh in
			func opening(along angle: Float, bottom: Float, width: Float, height: Float) {
				let mid = bottom + height / 2
				let radius = towerRadius(at: mid) + 0.00008
				// A thin slab facing out at `angle` round from +z, toward the back at π.
				let outward = SIMD2(sin(angle), cos(angle))
				let across = SIMD2(outward.y, -outward.x) * width / 2
				let center = outward * radius
				let depth = outward * 0.00012
				let outline = [center - across - depth, center + across - depth, center + across + depth, center - across + depth]
				mesh.addPrism(outline: Self.ordered(outline), bottom: bottom, top: bottom + height)
			}
			opening(along: .pi, bottom: plinthHeight, width: 0.0016, height: 0.0034)
			for (index, y) in [0.011, 0.018, 0.025].enumerated() {
				opening(along: index.isMultiple(of: 2) ? .pi * 0.85 : .pi * 1.15, bottom: Float(y), width: 0.0008, height: 0.0016)
			}
		}

		// The gallery: a corbel flaring out under the deck, the deck, and the railing round it.
		add(.iron) { mesh in
			mesh.addFrustum(sides: sides, bottomRadius: topRadius, topRadius: galleryRadius, bottom: towerTop - 0.0016, top: towerTop)
			mesh.addFrustum(sides: sides, bottomRadius: galleryRadius, topRadius: galleryRadius, bottom: towerTop, top: galleryTop)
			let edge = galleryRadius - 0.00015
			for i in 0..<lanternSides {
				let a = Float(i) / Float(lanternSides) * 2 * .pi
				let b = Float(i + 1) / Float(lanternSides) * 2 * .pi
				let p = SIMD3(cos(a) * edge, 0, sin(a) * edge)
				let q = SIMD3(cos(b) * edge, 0, sin(b) * edge)
				mesh.addStrut(from: p + [0, galleryTop, 0], to: p + [0, galleryTop + railHeight, 0], width: 0.00022)
				for y in [galleryTop + railHeight, galleryTop + railHeight * 0.5] {
					mesh.addStrut(from: p + [0, y, 0], to: q + [0, y, 0], width: 0.00016)
				}
			}
		}

		// The lantern: its parapet and the frame round the glass, the glass, and the cornice.
		add(.iron) { mesh in
			mesh.addFrustum(sides: lanternSides, bottomRadius: lanternRadius, topRadius: lanternRadius, bottom: galleryTop, top: glassBottom)
			for i in 0..<lanternSides {
				let a = Float(i) / Float(lanternSides) * 2 * .pi
				let corner = SIMD3(cos(a) * (lanternRadius + 0.00005), 0, sin(a) * (lanternRadius + 0.00005))
				mesh.addStrut(from: corner + [0, glassBottom, 0], to: corner + [0, glassTop, 0], width: 0.00022)
			}
			mesh.addFrustum(sides: lanternSides, bottomRadius: corniceRadius, topRadius: corniceRadius, bottom: glassTop, top: domeBottom)
		}
		add(.glass) { $0.addFrustum(sides: lanternSides, bottomRadius: lanternRadius - 0.00008, topRadius: lanternRadius - 0.00008, bottom: glassBottom, top: glassTop) }

		// The dome, the ventilator ball on it and the lightning rod.
		add(.dome) { mesh in
			mesh.addFrustum(sides: lanternSides, bottomRadius: corniceRadius - 0.0002, topRadius: corniceRadius * 0.55, bottom: domeBottom, top: domeBottom + domeRise * 0.55)
			mesh.addFrustum(sides: lanternSides, bottomRadius: corniceRadius * 0.55, topRadius: 0.0005, bottom: domeBottom + domeRise * 0.55, top: domeTop)
		}
		add(.metal) { mesh in
			mesh.addFrustum(sides: 8, bottomRadius: 0.0004, topRadius: 0.0007, bottom: domeTop - 0.0001, top: domeTop + ventHeight * 0.5)
			mesh.addFrustum(sides: 8, bottomRadius: 0.0007, topRadius: 0.0002, bottom: domeTop + ventHeight * 0.5, top: domeTop + ventHeight)
			mesh.addStrut(from: [0, domeTop + ventHeight - 0.0001, 0], to: [0, builtHeight, 0], width: 0.00018)
		}

		// The struts' corners stick a hair below the ground where they lean; stand it on y = 0.
		let lowest = parts.values.flatMap { $0.positions.map(\.y) }.min() ?? 0
		for part in Part.allCases {
			parts[part]?.translate(by: [0, -lowest, 0])
			if let scaled = parts[part]?.positions.map({ $0 * scale }) { parts[part]?.positions = scaled }
		}
		return parts
	}

	/// `outline` in order of increasing angle about its middle, as `addPrism` wants.
	private static func ordered(_ outline: [SIMD2<Float>]) -> [SIMD2<Float>] {
		let middle = outline.reduce(.zero, +) / Float(outline.count)
		return outline.sorted { atan2($0.y - middle.y, $0.x - middle.x) < atan2($1.y - middle.y, $1.x - middle.x) }
	}
}
