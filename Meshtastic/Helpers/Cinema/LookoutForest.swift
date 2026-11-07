//
//  LookoutForest.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/26.
//
import CoreGraphics
import Foundation
import simd

/// The conifers on the forested ground near the fire lookout, like the near forest of the painted
/// sunset (scripts/cinema/forest_view.py): stacked cones about 12.5 m tall, varied in size, shade
/// and turn, from just off the summit out to 2.6 km. Past that the ground's forest color stands in,
/// as in the painting. Only the parts that don't need RealityKit live here, so they can be tested.
enum LookoutForest {
	/// The summit is left clear this far out, as in the painting.
	static let nearest = 150.0
	/// Trees reach this far, then the ground's color stands in.
	static let farthest = 2_600.0
	/// Toward the far edge trees thin out, so the band fades into the ground instead of ending at a line.
	static let fadeFrom = 1_900.0
	/// Trees are this far apart near the summit…
	static let nearSpacing = 8.0
	/// …and farther out, this much of the view apart (about 1.25°), so the far band isn't
	/// packed with trees too small to see.
	static let angularSpacing = 0.022
	/// Closer than this a tree gets two cones; farther, one.
	static let nearDetail = 450.0
	/// The most triangles the trees may take, on top of the terrain's.
	static let triangleBudget = 250_000
	/// Shades of green across the palette, and light levels down it.
	static let shades = 8
	static let lightLevels = 16

	/// Where a tree stands and how it looks, by its true bearing (degrees) and distance from the site.
	struct Spot: Equatable {
		let bearing: Double
		let distance: Double
		/// 0.6–1.5, as in the painting, and a little larger in the far band.
		let scale: Double
		/// Radians about the vertical.
		let turn: Double
		let shade: Int
		/// Whether this spot survives the thinning at the summit's edge and the band's far edge.
		let kept: Bool
	}

	// MARK: Spots

	/// Every place a tree could stand, nearest first: rings whose spacing grows with distance,
	/// each spot jittered. The same every time, so turning the lookout keeps the same trees.
	static func spots() -> [Spot] {
		var result: [Spot] = []
		var distance = nearest
		var ring = 0
		while distance <= farthest {
			let spacing = max(nearSpacing, distance * angularSpacing)
			let count = max(1, Int(2 * .pi * distance / spacing))
			for index in 0..<count {
				let h = hash(ring, index)
				let jitterOut = (unit(h, 0) - 0.5) * 0.8 * spacing
				let jitterAround = (unit(h, 1) - 0.5) * 0.8
				let d = distance + jitterOut
				let bearing = (Double(index) + 0.5 + jitterAround) / Double(count) * 360
				// Thinned in over the first 90 m off the summit, like the painting's ramp, and
				// out over the far edge.
				let inner = smoothstep(nearest, nearest + 90, d)
				let outer = 1 - smoothstep(fadeFrom, farthest, d)
				let kept = d >= nearest && d <= farthest && unit(h, 2) < inner * outer
				// Far trees stand a little larger, so the band still reads as forest from the cab.
				let grown = 1 + 0.6 * smoothstep(nearDetail, farthest, d)
				result.append(Spot(
					bearing: bearing.truncatingRemainder(dividingBy: 360),
					distance: d,
					scale: (0.6 + 0.9 * unit(h, 3)) * grown,
					turn: unit(h, 4) * 2 * .pi,
					shade: min(shades - 1, Int(unit(h, 5) * Double(shades))),
					kept: kept
				))
			}
			distance += spacing
			ring += 1
		}
		return result
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

	/// The ground's height under a point, read from the terrain's own rings and spokes the way
	/// its triangles are drawn, so a tree stands on the surface that's shown rather than on the
	/// true ground, which can sit well above or below it between the far rings.
	static func groundElevation(bearing: Double, distance: Double, distances: [Double], elevations: [Float], spokes: Int) -> Float? {
		guard let first = distances.first, let last = distances.last, distance >= first, distance <= last else { return nil }
		let columns = spokes + 1
		// The ring just inside the point.
		var low = 0, high = distances.count - 1
		while high - low > 1 {
			let middle = (low + high) / 2
			if distances[middle] <= distance { low = middle } else { high = middle }
		}
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

	/// One tree's faces in meters around its base (east, up, north), turned by `turn` and scaled:
	/// each face its own three corners and its own normal, so the cones read faceted like the
	/// painting's low-poly ones.
	static func faces(turn: Double, scale: Double, near: Bool) -> [(corners: [SIMD3<Double>], normal: SIMD3<Double>)] {
		let cones = near ? nearCones : farCones
		let sides = near ? nearSides : farSides
		var result: [(corners: [SIMD3<Double>], normal: SIMD3<Double>)] = []
		for cone in cones {
			let tip = SIMD3<Double>(0, cone.tip * scale, 0)
			for side in 0..<sides {
				let a0 = turn + Double(side) / Double(sides) * 2 * .pi
				let a1 = turn + Double(side + 1) / Double(sides) * 2 * .pi
				let p0 = SIMD3(sin(a0) * cone.radius * scale, cone.base * scale, cos(a0) * cone.radius * scale)
				let p1 = SIMD3(sin(a1) * cone.radius * scale, cone.base * scale, cos(a1) * cone.radius * scale)
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

	/// The palette: shades across, light levels down, each lit the way the terrain's ground is,
	/// half its color in shadow and the rest by the warm sunset light.
	static func palette() -> CGImage? {
		let sunlight = SIMD3<Double>(1.0, 0.88, 0.76)
		var pixels = [UInt8](repeating: 255, count: shades * lightLevels * 4)
		for level in 0..<lightLevels {
			let lit = Double(level) / Double(lightLevels - 1)
			for shade in 0..<shades {
				let base = simd_mix(darkest, lightest, SIMD3(repeating: Double(shade) / Double(shades - 1)))
				let color = base * (0.5 + 0.5 * lit * sunlight)
				// Level 0 on the bottom row: texture v runs up from the bottom of the image.
				let offset = ((lightLevels - 1 - level) * shades + shade) * 4
				pixels[offset] = UInt8(clamping: Int(min(1, color.x) * 255))
				pixels[offset + 1] = UInt8(clamping: Int(min(1, color.y) * 255))
				pixels[offset + 2] = UInt8(clamping: Int(min(1, color.z) * 255))
			}
		}
		let space = CGColorSpaceCreateDeviceRGB()
		return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
			guard let context = CGContext(data: bytes.baseAddress, width: shades, height: lightLevels, bitsPerComponent: 8, bytesPerRow: shades * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
			return context.makeImage()
		}
	}

	/// Where in the palette a face of `shade` lit by `lit` (0–1) reads its color: a texel's center.
	static func paletteCoordinate(shade: Int, lit: Double) -> SIMD2<Float> {
		let level = Int((min(1, max(0, lit)) * Double(lightLevels - 1)).rounded())
		return SIMD2(Float((Double(shade) + 0.5) / Double(shades)), Float((Double(level) + 0.5) / Double(lightLevels)))
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

	private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
		let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
		return t * t * (3 - 2 * t)
	}
}
