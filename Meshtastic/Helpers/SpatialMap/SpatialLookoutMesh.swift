//
//  SpatialLookoutMesh.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
import CoreLocation
import Foundation
import simd

extension SpatialMeshData {
	/// A flat-shaded square pyramid, `halfWidth` from the center to each side at `bottom`, rising to
	/// a point at `top`, with a flat underside.
	mutating func addPyramid(halfWidth h: Float, bottom: Float, top: Float) {
		let apex = SIMD3<Float>(0, top, 0)
		for side in 0..<4 {
			let turn = simd_quatf(angle: Float(side) * .pi / 2, axis: [0, 1, 0])
			// The side facing +z, counterclockwise seen from outside, turned to each side in turn.
			let corners = [turn.act([-h, bottom, h]), turn.act([h, bottom, h]), apex]
			let normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
			let first = UInt32(positions.count)
			positions += corners
			normals += Array(repeating: normal, count: 3)
			indices += [first, first + 1, first + 2]
		}
		let first = UInt32(positions.count)
		positions += [[-h, bottom, -h], [h, bottom, -h], [h, bottom, h], [-h, bottom, h]]
		normals += Array(repeating: [0, -1, 0], count: 4)
		indices += [first, first + 1, first + 2, first, first + 2, first + 3]
	}
}

/// The fire lookout the cinema's lookout room stands on, drawn on the spatial map at the summit
/// chosen for it: a square cab glazed all round under a hipped roof with a lightning rod and a
/// railed catwalk, up on a tapered timber tower. The tower's four legs stand on concrete piers,
/// X-braced on every face, with switchback stairs climbing inside to a trapdoor in the catwalk.
/// About as tall as a router's tower.
enum SpatialLookout {
	/// The parts drawn in their own material.
	enum Part: CaseIterable {
		case stone
		case wall
		case glass
		case roof
		case wood
		case metal
	}

	/// The tower: from the ground to the underside of the catwalk.
	static let towerHeight: Float = 0.028
	static let baseHalf: Float = 0.0078
	static let topHalf: Float = 0.0046
	static let sections = 4
	static let legWidth: Float = 0.0007
	static let braceWidth: Float = 0.00028
	static let pierHalf: Float = 0.0009
	static let pierHeight: Float = 0.0008
	/// The cab and catwalk on top.
	static let deckHalf: Float = 0.008
	static let deckThickness: Float = 0.0006
	static let cabHalf: Float = 0.0055
	/// Heights above the deck's top.
	static let sillHeight: Float = 0.0035
	static let glassHeight: Float = 0.007
	static let headerHeight: Float = 0.001
	static let eaveHalf: Float = 0.0075
	static let roofRise: Float = 0.005
	static let rodHeight: Float = 0.0035
	static let railHeight: Float = 0.0032
	static let postWidth: Float = 0.0005
	static let railWidth: Float = 0.0003
	static let mullionWidth: Float = 0.00045
	/// Each flight of the stairs inside the tower: steps across, and the width of a tread.
	static let stepsPerFlight = 6
	static let stairWidth: Float = 0.0022
	static let triangleBudget = 1_800

	static var deckTop: Float { towerHeight + deckThickness }
	static var eaveHeight: Float { deckTop + sillHeight + glassHeight + headerHeight }
	/// From the ground to the tip of the lightning rod.
	static var height: Float { eaveHeight + roofRise + rodHeight }

	/// The true bearing the cab's front faces before it's turned, here and in the cinema's lookout
	/// room.
	static let frontHeading = 156.0

	/// How many steps the lookout turns in, all the way round.
	static let turnSteps = 16

	/// Where the cinema keeps how many sixteenth turns clockwise the lookout is turned.
	static let turnsKey = "cinemaLookoutSixteenthTurns"
	/// Where it kept them when the lookout turned in eighths.
	private static let eighthTurnsKey = "cinemaLookoutTurns"

	/// Carries a turn saved in eighths over to sixteenths, once.
	static func migrateEighthTurns(_ defaults: UserDefaults = .standard) {
		guard let eighths = defaults.object(forKey: eighthTurnsKey) as? Int else { return }
		if defaults.object(forKey: turnsKey) == nil {
			defaults.set(eighths * 2, forKey: turnsKey)
		}
		defaults.removeObject(forKey: eighthTurnsKey)
	}

	/// The bearing the cab faces after `turns` sixteenth turns clockwise.
	static func heading(turns: Int) -> Double {
		let step = 360 / Double(turnSteps)
		return (frontHeading + step * Double((turns % turnSteps + turnSteps) % turnSteps)).truncatingRemainder(dividingBy: 360)
	}

	/// The sixteenth turns that face the cab nearest to `bearing`, 0..<16.
	static func turns(nearest bearing: Double) -> Int {
		let steps = Int(((bearing - frontHeading) / (360 / Double(turnSteps))).rounded())
		return (steps % turnSteps + turnSteps) % turnSteps
	}

	/// Turn about y that points the model's front (+z) along `heading` on the map, where x runs
	/// east and z south.
	static func yaw(heading: Double = frontHeading) -> Float {
		Float(.pi - heading * .pi / 180)
	}

	static var yaw: Float { yaw() }

	/// Which way the cab faces, to the nearest of sixteen compass points.
	static func facing(heading: Double) -> String {
		switch Int(((heading + 11.25).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 22.5) {
		case 0: String(localized: "Faces north", comment: "Cinema: which way the fire lookout's cab faces")
		case 1: String(localized: "Faces north-northeast", comment: "Cinema: which way the fire lookout's cab faces")
		case 2: String(localized: "Faces northeast", comment: "Cinema: which way the fire lookout's cab faces")
		case 3: String(localized: "Faces east-northeast", comment: "Cinema: which way the fire lookout's cab faces")
		case 4: String(localized: "Faces east", comment: "Cinema: which way the fire lookout's cab faces")
		case 5: String(localized: "Faces east-southeast", comment: "Cinema: which way the fire lookout's cab faces")
		case 6: String(localized: "Faces southeast", comment: "Cinema: which way the fire lookout's cab faces")
		case 7: String(localized: "Faces south-southeast", comment: "Cinema: which way the fire lookout's cab faces")
		case 8: String(localized: "Faces south", comment: "Cinema: which way the fire lookout's cab faces")
		case 9: String(localized: "Faces south-southwest", comment: "Cinema: which way the fire lookout's cab faces")
		case 10: String(localized: "Faces southwest", comment: "Cinema: which way the fire lookout's cab faces")
		case 11: String(localized: "Faces west-southwest", comment: "Cinema: which way the fire lookout's cab faces")
		case 12: String(localized: "Faces west", comment: "Cinema: which way the fire lookout's cab faces")
		case 13: String(localized: "Faces west-northwest", comment: "Cinema: which way the fire lookout's cab faces")
		case 14: String(localized: "Faces northwest", comment: "Cinema: which way the fire lookout's cab faces")
		default: String(localized: "Faces north-northwest", comment: "Cinema: which way the fire lookout's cab faces")
		}
	}

	/// The coordinate in a lookout site's ID, "latitude,longitude"; nil for anything else.
	static func coordinate(siteID: String) -> CLLocationCoordinate2D? {
		let parts = siteID.split(separator: ",")
		guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]),
		      (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
		return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}

	/// Half the tower's width at height `y`, narrowing from the piers to the catwalk.
	static func towerHalf(at y: Float) -> Float {
		baseHalf + (topHalf - baseHalf) * min(max(y / towerHeight, 0), 1)
	}

	/// The heights the bracing meets the legs at, ground to top, evenly spaced.
	static var levels: [Float] {
		(0...sections).map { Float($0) * towerHeight / Float(sections) }
	}

	private static func square(_ half: Float) -> [SIMD2<Float>] {
		[[-half, -half], [half, -half], [half, half], [-half, half]]
	}

	/// The whole lookout standing on y = 0, centered on the origin, its front toward +z.
	static func geometry() -> [Part: SpatialMeshData] {
		var parts: [Part: SpatialMeshData] = [:]
		for part in Part.allCases { parts[part] = SpatialMeshData() }
		func add(_ part: Part, _ build: (inout SpatialMeshData) -> Void) {
			build(&parts[part, default: SpatialMeshData()])
		}
		let signs: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
		func leg(_ corner: Int, _ y: Float) -> SIMD3<Float> {
			let half = towerHalf(at: y)
			let sign = signs[corner % 4]
			return [sign.x * half, y, sign.y * half]
		}

		// Concrete piers under the legs, the legs, and on every face a girt at each level with an X
		// of bracing between.
		add(.stone) { mesh in
			for corner in 0..<4 {
				let foot = leg(corner, 0)
				mesh.addPrism(outline: square(pierHalf), bottom: 0, top: pierHeight, center: [foot.x, 0, foot.z])
			}
		}
		add(.wood) { mesh in
			for corner in 0..<4 {
				mesh.addStrut(from: leg(corner, pierHeight), to: leg(corner, towerHeight), width: legWidth)
			}
			let levels = levels
			for (index, low) in levels.dropLast().enumerated() {
				let high = levels[index + 1]
				let bottom = max(low, pierHeight)
				for face in 0..<4 {
					mesh.addStrut(from: leg(face, bottom), to: leg(face + 1, high), width: braceWidth)
					mesh.addStrut(from: leg(face + 1, bottom), to: leg(face, high), width: braceWidth)
					if index > 0 {
						mesh.addStrut(from: leg(face, low), to: leg(face + 1, low), width: braceWidth * 1.4)
					}
				}
			}
		}

		// Switchback stairs inside the tower: a flight up each section, back and forth along x,
		// with a landing at each end, the last one coming up under the trapdoor.
		add(.wood) { mesh in
			let levels = levels
			for (index, low) in levels.dropLast().enumerated() {
				let high = levels[index + 1]
				let reach = towerHalf(at: high) - legWidth * 1.5
				let start: Float = index.isMultiple(of: 2) ? -reach : reach
				let end = -start
				let z: Float = index.isMultiple(of: 2) ? -stairWidth / 2 - 0.0002 : stairWidth / 2 + 0.0002
				let rise = (high - low) / Float(stepsPerFlight)
				let run = (end - start) / Float(stepsPerFlight)
				for step in 0..<stepsPerFlight {
					let x0 = start + run * Float(step), x1 = x0 + run
					let top = low + rise * Float(step + 1)
					let outline: [SIMD2<Float>] = [[min(x0, x1), z - stairWidth / 2], [max(x0, x1), z - stairWidth / 2], [max(x0, x1), z + stairWidth / 2], [min(x0, x1), z + stairWidth / 2]]
					mesh.addPrism(outline: outline, bottom: top - 0.0003, top: top)
				}
				// The outer stringer, and the landing the flight arrives on.
				let side = z + (z < 0 ? -stairWidth / 2 : stairWidth / 2)
				mesh.addStrut(from: [start, low, side], to: [end, high, side], width: braceWidth)
				if index < levels.count - 2 {
					let back = end > 0 ? end - 0.0018 : end + 0.0018
					let reach = stairWidth + 0.0002
					let landing: [SIMD2<Float>] = [[min(end, back), -reach], [max(end, back), -reach], [max(end, back), reach], [min(end, back), reach]]
					mesh.addPrism(outline: landing, bottom: high - 0.0003, top: high)
				}
			}
		}

		// The catwalk deck on the tower top.
		add(.wood) { $0.addPrism(outline: square(deckHalf), bottom: towerHeight, top: deckTop) }

		// The cab: plain walls to the sill, glass all round, a header above it.
		let sill = deckTop + sillHeight
		let head = sill + glassHeight
		add(.wall) { $0.addPrism(outline: square(cabHalf), bottom: deckTop, top: sill) }
		add(.glass) { $0.addPrism(outline: square(cabHalf - 0.0002), bottom: sill, top: head) }
		add(.wall) { $0.addPrism(outline: square(cabHalf), bottom: head, top: eaveHeight) }
		// Mullions: the corners and two between them on each side, standing just proud of the glass.
		add(.wall) { mesh in
			let out = cabHalf - 0.00005
			for i in 0..<4 {
				let along = -out + Float(i) * 2 * out / 3
				let isCorner = i == 0 || i == 3
				// The front and back draw the corners; the sides only their middle two.
				var spots: [SIMD2<Float>] = [[along, out], [along, -out]]
				if !isCorner { spots += [[out, along], [-out, along]] }
				for spot in spots {
					mesh.addStrut(from: [spot.x, sill, spot.y], to: [spot.x, head, spot.y], width: mullionWidth)
				}
			}
		}

		// The hipped roof over wide eaves, a thin fascia under its edge, and the lightning rod.
		add(.roof) { mesh in
			mesh.addPrism(outline: square(eaveHalf), bottom: eaveHeight - 0.0005, top: eaveHeight)
			mesh.addPyramid(halfWidth: eaveHalf, bottom: eaveHeight, top: eaveHeight + roofRise)
		}
		let peak = eaveHeight + roofRise
		add(.metal) { $0.addStrut(from: [0, peak - 0.0005, 0], to: [0, peak + rodHeight, 0], width: 0.0003) }

		// The catwalk railing: posts round the edge with a top and middle rail.
		add(.wood) { mesh in
			let edge = deckHalf - postWidth / 2
			let spacing = 2 * edge / 4
			for side in 0..<4 {
				let turn = simd_quatf(angle: Float(side) * .pi / 2, axis: [0, 1, 0])
				func point(_ along: Float, _ y: Float) -> SIMD3<Float> { turn.act([along, y, edge]) }
				let stops: [Float] = (0...4).map { -edge + Float($0) * spacing }
				// Each corner post is drawn by the side it starts.
				for along in stops.dropLast() {
					mesh.addStrut(from: point(along, deckTop), to: point(along, deckTop + railHeight), width: postWidth)
				}
				for y in [deckTop + railHeight, deckTop + railHeight * 0.5] {
					mesh.addStrut(from: point(-edge, y), to: point(edge, y), width: railWidth)
				}
			}
		}

		// The struts' corners stick a hair below the ground where they lean; stand it on y = 0.
		let lowest = parts.values.flatMap { $0.positions.map(\.y) }.min() ?? 0
		for part in Part.allCases { parts[part]?.translate(by: [0, -lowest, 0]) }
		return parts
	}
}

/// Where the lookout stands when nodes are on its summit.
enum SpatialLookoutSpot {
	/// The summit itself when no pin is within `clearance`, else the nearest spot around it that
	/// clears every pin, trying behind the cab (facing `heading`) first. Nil means stand on the
	/// summit. When nothing clears them all, the spot that keeps farthest from the nearest one.
	static func spot(summit: SIMD2<Float>, pins: [SIMD2<Float>], clearance: Float, heading: Double = SpatialLookout.frontHeading) -> SIMD2<Float>? {
		func room(_ point: SIMD2<Float>) -> Float {
			pins.map { simd_distance($0, point) }.min() ?? .infinity
		}
		guard room(summit) < clearance else { return nil }
		// Behind the cab, then alternately either side of it, round to the front.
		let back = Float(heading * .pi / 180) + .pi
		let steps = 12
		var candidates: [SIMD2<Float>] = []
		for ring in [clearance, clearance * 2] {
			for index in 0...steps / 2 {
				for sign: Float in index == 0 || index == steps / 2 ? [1] : [1, -1] {
					let angle = back + sign * Float(index) * 2 * .pi / Float(steps)
					candidates.append(summit + SIMD2(sin(angle), -cos(angle)) * ring)
				}
			}
		}
		return candidates.first { room($0) >= clearance } ?? candidates.max { room($0) < room($1) }
	}
}
