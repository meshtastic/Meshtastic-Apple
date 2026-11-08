//
//  LookoutForest.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/26.
//
import CoreGraphics
import Foundation
import simd

/// The forest on the ground seen from the fire lookout, like the painted sunset's
/// (scripts/cinema/forest_view.py): true-size conifers packed so they overlap into a carpet of
/// treetops that shrinks and hazes with distance. Within `rowsFrom` each tree is the painting's
/// stacked cones. Farther out, where one tree is only a few pixels, the forest is drawn as rows:
/// strips standing on the ground and facing the cab, each painted with a row of the painting's
/// trees, see-through between their tops. Rows stack one behind another so the slopes fill with
/// trees the way the painting's do. Everything goes only where it'd show: on forested ground above
/// the sill's line and not behind nearer ground. Only the parts that don't need RealityKit live
/// here, so they can be tested.
enum LookoutForest {
	/// The summit is left clear this far out, as in the painting.
	static let nearest = 150.0
	/// The forest thins out from `fadeFrom` and stops at `reach`, where the haze has taken the hills.
	static let fadeFrom = 10_000.0
	static let reach = 15_000.0
	/// Nothing lower than this below the horizon shows over the sill: it is 0.94 m high and 2.2 m
	/// out from a 1.15 m seated eye (KNEE, SILL and EYE_HEIGHT in scripts/cinema/fire_lookout.py).
	static let sillDepression = 5.5
	/// Earth's radius with refraction, as `LookoutTerrain` uses: far ground sits below a flat horizon.
	static let earthRadius = 7_450_000.0
	/// Near trees are this far apart, about the painting's one tree to 30 m².
	static let nearSpacing = 5.5
	/// Closer than this a tree gets two cones; farther, one.
	static let nearDetail = 450.0
	/// From here out the forest is rows.
	static let rowsFrom = 1_500.0
	/// Each row stands this much farther out than the one before it.
	static let rowStep = 0.012
	/// A row's strip: how tall, and how much forest its texture shows across.
	static let rowHeight = 24.0
	static let rowTextureMeters = 140.0
	/// Past this a row's trees stop shrinking in the view: they're drawn larger, wider and taller
	/// together, as big in the view as a true-size tree here, about the painting's middle trees.
	/// A forest seen from a high summit, kilometers out, still shows trees rather than texture.
	static let rowGrowFrom = 2_000.0

	/// How many times true size a row `distance` out is drawn: 1 near, 5× at 10 km.
	static func rowScale(at distance: Double) -> Double {
		max(1, distance / rowGrowFrom)
	}
	/// Where the forest first shows past the near trees in a direction, its first stretch is the
	/// painting's front band: big 3D trees, `frontBoost` times a row's size at the front, shrinking
	/// to a row's size `frontDepth` times as far out. On a high, steep summit that's the closest
	/// forest in view, kilometers out, and without it the view has no trees in front of the carpet.
	static let frontDepth = 1.2
	static let frontBoost = 2.5
	/// The most triangles the front band may take, of the forest's.
	static let frontBudget = 250_000

	/// How many times true size a front tree `distance` out is drawn, with the band starting at `front`.
	static func frontScale(at distance: Double, from front: Double) -> Double {
		let along = min(1, max(0, log(distance / front) / log(frontDepth)))
		return rowScale(at: distance) * (1 + (frontBoost - 1) * (1 - along))
	}

	/// The most triangles the forest may take, on top of the terrain's.
	static let triangleBudget = 600_000
	/// Shades of green across the palette, and light levels down it.
	static let shades = 8
	static let lightLevels = 16
	/// Haze levels, from none to `maxHaze`, the haze at about 23 km.
	static let hazeLevels = 8
	static let maxHaze = 0.6
	/// The painting's haze: a cool gray, taking half the view by about 17 km (forest_view.py's
	/// `1 - exp(-d / 25 km)`). The terrain uses it too, so far ridges fade the way the painting's do.
	static let hazeColor = SIMD3<Double>(0.60, 0.60, 0.62)
	static let hazeDistance = 25_000.0

	/// Where a tree stands and how it looks, by its true bearing (degrees) and distance from the site.
	struct Spot: Equatable {
		let bearing: Double
		let distance: Double
		/// 0.6–1.5 times the painting's 12.5 m tree, across and up.
		let width: Double
		let height: Double
		/// Radians about the vertical.
		let turn: Double
		let shade: Int
		/// 0..<1, for thinning toward the far edge.
		let chance: Double
	}

	/// How likely a tree is to stand at `distance`: all of them out to `fadeFrom`, then fewer to
	/// none at `reach`, so the forest has no hard edge.
	static func density(at distance: Double) -> Double {
		1 - smoothstep(fadeFrom, reach, distance)
	}

	// MARK: Spots

	/// Calls `body` with every place a near tree could stand out to `farthest`, nearest first:
	/// rings `nearSpacing` apart, each spot jittered. The same every time, so turning the
	/// lookout keeps the same trees. Stops when `body` returns false.
	static func forEachSpot(farthest: Double, _ body: (Spot) -> Bool) {
		var distance = nearest
		var ring = 0
		while distance <= farthest {
			let spacing = nearSpacing
			let count = max(1, Int(2 * .pi * distance / spacing))
			for index in 0..<count {
				let h = hash(ring, index)
				let d = distance + (unit(h, 0) - 0.5) * 0.8 * spacing
				let size = 0.6 + 0.9 * unit(h, 3)
				let bearing = (Double(index) + 0.5 + (unit(h, 1) - 0.5) * 0.8) / Double(count) * 360
				let spot = Spot(
					bearing: bearing.truncatingRemainder(dividingBy: 360),
					distance: d,
					width: size,
					height: size,
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

	/// Calls `body` with every place a front tree could stand across `spoke`, from `front` out
	/// through the band, nearest first: spaced like the near trees at the trees' drawn size, each
	/// jittered and sized. The same every time. Stops when `body` returns false.
	static func forEachFrontSpot(spoke: Int, spokes: Int, from front: Double, _ body: (Spot) -> Bool) {
		let spokeWidth = 360 / Double(spokes)
		var distance = front
		var step = 0
		while distance < front * frontDepth {
			let scale = frontScale(at: distance, from: front)
			let spacing = nearSpacing * scale
			let count = max(1, Int((distance * spokeWidth * .pi / 180 / spacing).rounded()))
			for index in 0..<count {
				let h = hash(spoke + 2_000_000, step * 1_024 + index)
				let size = (0.6 + 0.9 * unit(h, 3)) * scale
				let across = (Double(index) + 0.5 + (unit(h, 1) - 0.5) * 0.8) / Double(count)
				let spot = Spot(
					bearing: ((Double(spoke) + across) * spokeWidth).truncatingRemainder(dividingBy: 360),
					distance: distance + (unit(h, 0) - 0.5) * 0.8 * spacing,
					width: size,
					height: size,
					turn: unit(h, 4) * 2 * .pi,
					shade: min(shades - 1, Int(unit(h, 5) * Double(shades))),
					chance: unit(h, 2)
				)
				guard body(spot) else { return }
			}
			distance += spacing
			step += 1
		}
	}

	/// How high the nearer ground reaches in the cab's view at each of the terrain's samples, as the
	/// tangent of its angle above the eye's horizontal: ground behind it is hidden.
	static func horizon(distances: [Double], elevations: [Float], spokes: Int, eye: Double) -> [Double] {
		let columns = spokes + 1
		var horizon = [Double](repeating: -.infinity, count: distances.count * columns)
		for spoke in 0..<spokes {
			var highest = -Double.infinity
			for (ring, distance) in distances.enumerated() {
				let index = ring * columns + spoke
				horizon[index] = highest
				highest = max(highest, slope(elevation: Double(elevations[index]), distance: distance, eye: eye))
			}
		}
		return horizon
	}

	/// A point's height in the cab's view, as the tangent of its angle above the eye's horizontal,
	/// with the Earth's curve taken off.
	static func slope(elevation: Double, distance: Double, eye: Double) -> Double {
		(elevation - eye - distance * distance / (2 * earthRadius)) / distance
	}

	/// Whether a tree whose top stands at `top` shows over the sill and over `horizon`, the nearer
	/// ground's height in the view.
	static func shows(top: Double, distance: Double, eye: Double, horizon: Double) -> Bool {
		let angle = slope(elevation: top, distance: distance, eye: eye)
		return angle > -tan(sillDepression * .pi / 180) && angle > horizon
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

	/// Triangles one near tree takes at `distance`.
	static func triangles(at distance: Double) -> Int {
		distance < nearDetail ? nearCones.count * nearSides : farCones.count * farSides
	}

	// MARK: Rows

	/// One strip of forest: `distance` out, across the terrain's spoke `spoke`, its texture starting
	/// `offset` (0–1) of the way along the row of painted trees.
	struct Row: Equatable {
		let distance: Double
		let spoke: Int
		let offset: Double
		/// 0..<1, for thinning toward the far edge.
		let chance: Double
	}

	/// Calls `body` with every row out to `farthest`, nearest first, one per spoke at each step,
	/// jittered so the rows don't line up. The same every time. Stops when `body` returns false.
	static func forEachRow(farthest: Double, spokes: Int, _ body: (Row) -> Bool) {
		var distance = rowsFrom
		var step = 0
		while distance <= farthest {
			for spoke in 0..<spokes {
				let h = hash(step + 1_000_000, spoke)
				let row = Row(
					distance: distance * (1 + rowStep * (unit(h, 0) - 0.5) * 0.8),
					spoke: spoke,
					offset: unit(h, 1),
					chance: unit(h, 2)
				)
				guard body(row) else { return }
			}
			distance *= 1 + rowStep
			step += 1
		}
	}

	/// The texture's bands: a haze level, and which side the sun lights.
	static var rowBands: Int { hazeLevels * 2 }

	/// The part of the row texture a strip `width` meters across shows: its own stretch of the row,
	/// in the band for its haze and the side the sun is on. A strip wider than the texture shows
	/// all of it, stretched.
	struct RowCoordinates: Equatable {
		let u0: Float
		let u1: Float
		let v0: Float
		let v1: Float
	}

	static func rowCoordinates(offset: Double, width: Double, distance: Double, sunOnRight: Bool) -> RowCoordinates {
		let span = min(1, width / (rowTextureMeters * rowScale(at: distance)))
		let u0 = offset * (1 - span)
		let fog = 1 - exp(-distance / hazeDistance)
		let level = Int((min(1, fog / maxHaze) * Double(hazeLevels - 1)).rounded())
		let band = Double(level * 2 + (sunOnRight ? 1 : 0))
		// Inset a little, so sampling never reaches the next band.
		return RowCoordinates(u0: Float(u0), u1: Float(u0 + span), v0: Float((band + 0.01) / Double(rowBands)), v1: Float((band + 0.97) / Double(rowBands)))
	}

	/// The row texture: bands of the painting's trees, packed in two layers so they overlap,
	/// each band hazed to its level and lit from the left or the right. Transparent above the
	/// treetops, so the hills behind show between them; a solid strip of canopy at the bottom, so
	/// no row shows the ground through its trees' feet.
	static func rowTexture(width: Int = 1_024, bandHeight: Int = 128) -> CGImage? {
		let height = bandHeight * rowBands
		let space = CGColorSpaceCreateDeviceRGB()
		guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
		let sunlight = SIMD3<Double>(1.0, 0.88, 0.76)
		let pixelsPerMeter = Double(width) / rowTextureMeters
		let rise = Double(bandHeight - 4) / rowHeight
		func cgColor(_ c: SIMD3<Double>) -> CGColor {
			CGColor(colorSpace: space, components: [CGFloat(min(1, c.x)), CGFloat(min(1, c.y)), CGFloat(min(1, c.z)), 1]) ?? CGColor(gray: 0, alpha: 1)
		}
		// The painting's tree: three stacked cones.
		let tiers = [Cone(radius: 2.4, base: 2, tip: 8), Cone(radius: 1.8, base: 5.5, tip: 10.5), Cone(radius: 1.1, base: 8.5, tip: 12.5)]
		for band in 0..<rowBands {
			let fog = maxHaze * Double(band / 2) / Double(hazeLevels - 1)
			let sunOnRight = band % 2 == 1
			let floor = Double(band * bandHeight + 2)
			func hazed(_ c: SIMD3<Double>, extra: Double = 0) -> SIMD3<Double> {
				simd_mix(c, hazeColor, SIMD3(repeating: min(1, fog + extra)))
			}
			// Canopy at the trees' feet, low and in the trees' own shadow color, so where one row
			// stands over the next it doesn't draw a dark line.
			context.setFillColor(cgColor(hazed(simd_mix(darkest, lightest, SIMD3(repeating: 0.4)) * 0.55)))
			context.fill(CGRect(x: 0, y: floor, width: Double(width), height: 1.5 * rise))
			// Two layers: the back one smaller, darker and a touch hazier, then the front one.
			for layer in 0..<2 {
				let count = Int(rowTextureMeters / (layer == 0 ? 2.6 : 3.2))
				for index in 0..<count {
					let h = hash(band * 7 + layer, index)
					let size = (0.6 + 0.9 * unit(h, 0)) * (layer == 0 ? 0.85 : 1)
					let x = (Double(index) + unit(h, 1)) / Double(count) * Double(width)
					let base = simd_mix(darkest, lightest, SIMD3(repeating: unit(h, 2)))
					let lit = hazed(base * (0.55 + 0.45 * sunlight) * (layer == 0 ? 0.85 : 1), extra: layer == 0 ? 0.03 : 0)
					let shadow = hazed(base * 0.55 * (layer == 0 ? 0.85 : 1), extra: layer == 0 ? 0.03 : 0)
					for tier in tiers {
						let r = tier.radius * size * pixelsPerMeter
						let y0 = floor + tier.base * size * rise
						let y1 = floor + tier.tip * size * rise
						for (side, color) in [(-1.0, sunOnRight ? shadow : lit), (1.0, sunOnRight ? lit : shadow)] {
							context.setFillColor(cgColor(color))
							context.beginPath()
							context.move(to: CGPoint(x: x, y: y0))
							context.addLine(to: CGPoint(x: x + side * r, y: y0))
							context.addLine(to: CGPoint(x: x, y: y1))
							context.closePath()
							context.fillPath()
						}
					}
				}
			}
		}
		return context.makeImage()
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
