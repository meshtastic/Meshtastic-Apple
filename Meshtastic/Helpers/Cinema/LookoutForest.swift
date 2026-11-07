//
//  LookoutForest.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/26.
//
import CoreGraphics
import Foundation
import simd

/// The conifers on the forested ground seen from the fire lookout, like the near forest of the
/// painted sunset (scripts/cinema/forest_view.py): stacked cones varied in size, shade and turn.
/// The painting's gentle summit shows its trees just past the tower. A real mountain falls away
/// steeply, and the ground for kilometers around sits under the cab's sill, so the trees go on the
/// first forested ground that shows above the sill in each direction: a band from there out to
/// `bandDepth` times as far. They're drawn as stands about as tall in the view as the painting's
/// trees, so the band reads as a tree line rather than specks. Only the parts that don't need
/// RealityKit live here, so they can be tested.
enum LookoutForest {
	/// The summit is left clear this far out, as in the painting.
	static let nearest = 150.0
	/// The painting's trees stand out to 2.6 km; a tree that far keeps its own size, and a farther
	/// one is drawn as a stand that looks as tall from the cab.
	static let paintedReach = 2_400.0
	/// Each band runs from the first forested ground in view out to this many times as far.
	static let bandDepth = 1.35
	/// Nothing lower than this below the horizon shows over the sill: it is 0.94 m high and 2.2 m
	/// out from a 1.15 m seated eye (KNEE, SILL and EYE_HEIGHT in scripts/cinema/fire_lookout.py).
	static let sillDepression = 5.5
	/// Earth's radius with refraction, as `LookoutTerrain` uses: far ground sits below a flat horizon.
	static let earthRadius = 7_450_000.0
	/// Trees are this far apart near the summit…
	static let nearSpacing = 8.0
	/// …and farther out, this much of the view apart (about 0.26°), a dense fringe like the painting's.
	static let angularSpacing = 0.0045
	/// Closer than this a tree gets two cones; farther, one.
	static let nearDetail = 450.0
	/// The most triangles the trees may take, on top of the terrain's.
	static let triangleBudget = 300_000
	/// Shades of green across the palette, and light levels down it.
	static let shades = 8
	static let lightLevels = 16
	/// Haze levels across the palette, from none to `maxHaze`, the haze at about 40 km.
	static let hazeLevels = 8
	static let maxHaze = 0.5
	/// The terrain's haze: its color, and how far it takes to cover half the view.
	static let hazeColor = SIMD3<Double>(0.78, 0.73, 0.70)
	static let hazeDistance = 60_000.0

	/// Where a tree stands and how it looks, by its true bearing (degrees) and distance from the site.
	struct Spot: Equatable {
		let bearing: Double
		let distance: Double
		/// Across: 0.6–1.5 as in the painting, times how much farther than the painting's trees it
		/// stands, so a far stand is as wide in the view.
		let width: Double
		/// Up: the same, but growing more slowly with distance, so a far stand reads as canopy
		/// rather than a spike.
		let height: Double
		/// Radians about the vertical.
		let turn: Double
		let shade: Int
		/// 0..<1, for thinning the band's edges.
		let chance: Double
	}

	/// The stretch of one direction trees are planted in.
	struct Band: Equatable {
		let start: Double
		let end: Double

		/// How likely a tree is to stand `distance` along the band: thinning in over its first fifth
		/// and out over its far part, so it has no hard edge.
		func density(at distance: Double) -> Double {
			let t = (distance - start) / max(end - start, 1)
			return LookoutForest.smoothstep(0, 0.2, t) * (1 - LookoutForest.smoothstep(0.55, 1, t))
		}
	}

	// MARK: Spots

	/// Calls `body` with every place a tree could stand out to `farthest`, nearest first: rings
	/// whose spacing grows with distance, each spot jittered. The same every time, so turning the
	/// lookout keeps the same trees. Stops when `body` returns false.
	static func forEachSpot(farthest: Double, _ body: (Spot) -> Bool) {
		var distance = nearest
		var ring = 0
		while distance <= farthest {
			let spacing = max(nearSpacing, distance * angularSpacing)
			let count = max(1, Int(2 * .pi * distance / spacing))
			for index in 0..<count {
				let h = hash(ring, index)
				let d = distance + (unit(h, 0) - 0.5) * 0.8 * spacing
				let size = 0.6 + 0.9 * unit(h, 3)
				let grown = max(1, d / paintedReach)
				let bearing = (Double(index) + 0.5 + (unit(h, 1) - 0.5) * 0.8) / Double(count) * 360
				let spot = Spot(
					bearing: bearing.truncatingRemainder(dividingBy: 360),
					distance: d,
					width: size * grown,
					height: size * pow(grown, 0.6),
					turn: unit(h, 4) * 2 * .pi,
					shade: min(shades - 1, Int(unit(h, 5) * Double(shades))),
					chance: unit(h, 2)
				)
				guard body(spot) else { return }
			}
			distance += spacing
			ring += 1
		}
	}

	/// What the cab sees in each direction, from the terrain's rings and spokes: the band trees go
	/// in (or nil where no forest shows), and how high the nearer ground reaches in the view at
	/// each sample, as the tangent of its angle above the eye's horizontal.
	struct View {
		let bands: [Band?]
		let horizon: [Double]
	}

	/// Walks out each spoke. Ground shows when it's above the sill's line and above every nearer
	/// sample; the band starts at the first such sample that's forest.
	static func view(distances: [Double], elevations: [Float], spokes: Int, eye: Double, isForest: (_ index: Int) -> Bool) -> View {
		let columns = spokes + 1
		let sill = -tan(sillDepression * .pi / 180)
		var bands = [Band?](repeating: nil, count: spokes)
		var horizon = [Double](repeating: -.infinity, count: distances.count * columns)
		for spoke in 0..<spokes {
			var highest = -Double.infinity
			for (ring, distance) in distances.enumerated() {
				let index = ring * columns + spoke
				horizon[index] = highest
				let slope = (Double(elevations[index]) - eye - distance * distance / (2 * earthRadius)) / distance
				if bands[spoke] == nil, distance >= nearest, slope > sill, slope >= highest, isForest(index) {
					bands[spoke] = Band(start: distance, end: distance * bandDepth)
				}
				highest = max(highest, slope)
			}
		}
		return View(bands: bands, horizon: horizon)
	}

	/// Whether trees grow on this ground: forest in the basemap's land cover, or with no land
	/// cover, where the ground color's height fallback paints forest. Never near the snow line.
	static func isForest(cover: OfflineLandCover?, elevation: Double, latitude: Double, heightFraction: Double) -> Bool {
		guard elevation < LookoutGroundColor.snowLine(latitude: latitude) - 300 else { return false }
		switch cover {
		case .forest: return true
		case nil: return elevation > 0.5 && heightFraction < LookoutGroundColor.forestBandTop
		default: return false
		}
	}

	/// The ring just inside `distance`, by the terrain's ring distances (nearest first).
	static func ring(inside distance: Double, distances: [Double]) -> Int {
		var low = 0, high = distances.count - 1
		while high - low > 1 {
			let middle = (low + high) / 2
			if distances[middle] <= distance { low = middle } else { high = middle }
		}
		return low
	}

	/// The ground's height under a point, read from the terrain's own rings and spokes the way
	/// its triangles are drawn, so a tree stands on the surface that's shown rather than on the
	/// true ground, which can sit well above or below it between the far rings.
	static func groundElevation(bearing: Double, distance: Double, distances: [Double], elevations: [Float], spokes: Int) -> Float? {
		guard let first = distances.first, let last = distances.last, distance >= first, distance <= last else { return nil }
		let columns = spokes + 1
		let low = ring(inside: distance, distances: distances)
		let high = min(low + 1, distances.count - 1)
		let outward = Float((distance - distances[low]) / max(distances[high] - distances[low], 1e-9))
		let around = bearing / 360 * Double(spokes)
		let spoke = min(spokes - 1, max(0, Int(around)))
		let across = Float(around - Double(spoke))
		func at(_ ring: Int, _ spoke: Int) -> Float { elevations[ring * columns + spoke] }
		let inner = at(low, spoke) + (at(low, spoke + 1) - at(low, spoke)) * across
		let outer = at(high, spoke) + (at(high, spoke + 1) - at(high, spoke)) * across
		return inner + (outer - inner) * outward
	}

	// MARK: Shape

	/// A cone of a tree, in meters: its radius at the base, and its base and tip above the ground.
	struct Cone {
		let radius: Double
		let base: Double
		let tip: Double
	}

	/// Close up, two cones like the painting's stacked ones; the trunk never shows from the cab.
	static let nearCones = [Cone(radius: 2.4, base: 1.5, tip: 9.5), Cone(radius: 1.6, base: 6.5, tip: 12.5)]
	static let nearSides = 6
	/// Farther out, one cone.
	static let farCones = [Cone(radius: 2.4, base: 1.5, tip: 12.5)]
	static let farSides = 5

	/// Triangles one tree takes at `distance`.
	static func triangles(at distance: Double) -> Int {
		distance < nearDetail ? nearCones.count * nearSides : farCones.count * farSides
	}

	/// One tree's faces in meters around its base (east, up, north), turned by `turn` and sized:
	/// each face its own three corners and its own normal, so the cones read faceted like the
	/// painting's low-poly ones.
	static func faces(turn: Double, width: Double, height: Double, near: Bool) -> [(corners: [SIMD3<Double>], normal: SIMD3<Double>)] {
		let cones = near ? nearCones : farCones
		let sides = near ? nearSides : farSides
		var result: [(corners: [SIMD3<Double>], normal: SIMD3<Double>)] = []
		for cone in cones {
			let tip = SIMD3<Double>(0, cone.tip * height, 0)
			for side in 0..<sides {
				let a0 = turn + Double(side) / Double(sides) * 2 * .pi
				let a1 = turn + Double(side + 1) / Double(sides) * 2 * .pi
				let p0 = SIMD3(sin(a0) * cone.radius * width, cone.base * height, cos(a0) * cone.radius * width)
				let p1 = SIMD3(sin(a1) * cone.radius * width, cone.base * height, cos(a1) * cone.radius * width)
				var normal = simd_normalize(simd_cross(p1 - p0, tip - p0))
				if normal.y < 0 { normal = -normal }
				result.append(([p0, p1, tip], normal))
			}
		}
		return result
	}

	// MARK: Color

	/// The painting's needle greens, from its darkest to its lightest, as sRGB for an unlit material.
	static let darkest = SIMD3<Double>(0.11, 0.19, 0.12)
	static let lightest = SIMD3<Double>(0.22, 0.28, 0.17)

	/// The palette: shades within each haze level across, light levels down. Each is lit the way the
	/// terrain's ground is, half its color in shadow and the rest by the warm sunset light, then
	/// faded into the terrain's haze, so a tree is as hazy as the ground it stands on.
	static func palette() -> CGImage? {
		let sunlight = SIMD3<Double>(1.0, 0.88, 0.76)
		let width = shades * hazeLevels
		var pixels = [UInt8](repeating: 255, count: width * lightLevels * 4)
		for level in 0..<lightLevels {
			let lit = Double(level) / Double(lightLevels - 1)
			for column in 0..<width {
				let shade = column % shades
				let fog = maxHaze * Double(column / shades) / Double(hazeLevels - 1)
				let base = simd_mix(darkest, lightest, SIMD3(repeating: Double(shade) / Double(shades - 1)))
				let color = simd_mix(base * (0.5 + 0.5 * lit * sunlight), hazeColor, SIMD3(repeating: fog))
				// Level 0 on the bottom row: texture v runs up from the bottom of the image.
				let offset = ((lightLevels - 1 - level) * width + column) * 4
				pixels[offset] = UInt8(clamping: Int(min(1, color.x) * 255))
				pixels[offset + 1] = UInt8(clamping: Int(min(1, color.y) * 255))
				pixels[offset + 2] = UInt8(clamping: Int(min(1, color.z) * 255))
			}
		}
		let space = CGColorSpaceCreateDeviceRGB()
		return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
			guard let context = CGContext(data: bytes.baseAddress, width: width, height: lightLevels, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
			return context.makeImage()
		}
	}

	/// Where in the palette a face of `shade`, lit by `lit` (0–1), `distance` meters away reads its
	/// color: a texel's center.
	static func paletteCoordinate(shade: Int, lit: Double, distance: Double) -> SIMD2<Float> {
		let level = Int((min(1, max(0, lit)) * Double(lightLevels - 1)).rounded())
		let fog = 1 - exp(-distance / hazeDistance)
		let haze = Int((min(1, fog / maxHaze) * Double(hazeLevels - 1)).rounded())
		let column = haze * shades + shade
		return SIMD2(Float((Double(column) + 0.5) / Double(shades * hazeLevels)), Float((Double(level) + 0.5) / Double(lightLevels)))
	}

	// MARK: Helpers

	private static func hash(_ a: Int, _ b: Int) -> UInt64 {
		var x = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(bitPattern: Int64(b)) &* 0xC2B2_AE3D_27D4_EB4F
		x ^= x >> 31
		x = x &* 0xBF58_476D_1CE4_E5B9
		x ^= x >> 27
		return x
	}

	/// A number in 0..<1 from the hash, a different one for each `slot`.
	private static func unit(_ hash: UInt64, _ slot: UInt64) -> Double {
		var x = hash &+ slot &* 0x94D0_49BB_1331_11EB
		x ^= x >> 30
		x = x &* 0xBF58_476D_1CE4_E5B9
		x ^= x >> 27
		x = x &* 0x94D0_49BB_1331_11EB
		x ^= x >> 31
		return Double(x >> 11) / Double(1 << 53)
	}

	fileprivate static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
		let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
		return t * t * (3 - 2 * t)
	}
}
