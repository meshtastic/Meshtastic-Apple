//
//  TerrainOcclusion.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//
//  How much of the sky each point of a terrain tile sees: the mean, over a few directions, of how
//  high the ground around it rises. Valley floors and gorges see less sky than ridges, so blended
//  into the hillshade they read as deep instead of flat.
//

import Foundation

enum TerrainOcclusion {
	/// Directions looked along from each point.
	static let directions = 8
	/// How far out the rising ground is looked for, in meters.
	static let radiusMeters = 1_000.0
	/// The most samples a look goes out, and so the margin a tile needs. At zoom 12 a sample is
	/// about 26 m at 47°, so this reaches the full kilometer; closer in, the look gets shorter.
	static let maxRadiusSamples = 32

	/// How many samples out to look for a tile whose samples are `metersPerSample` apart.
	static func radiusSamples(metersPerSample: Double) -> Int {
		min(maxRadiusSamples, max(2, Int((radiusMeters / max(metersPerSample, 0.01)).rounded(.up))))
	}

	/// Distances along a look, in samples: every sample to 6, then a quarter further each step,
	/// ending at `radius` itself so the far edge of the look is always read.
	static func steps(radius: Int) -> [Int] {
		var result: [Int] = []
		var distance = 1
		while distance <= radius {
			result.append(distance)
			distance = max(distance + 1, Int(Double(distance) * 1.25))
		}
		if let last = result.last, last < radius {
			result.append(radius)
		}
		return result
	}

	/// One byte per sample of the tile, row-major, not counting its margin: 0 where the ground
	/// around never rises above the point (open slopes, summits), toward 255 at the bottom of a deep
	/// valley. Each look takes the steepest rise along it, `rise / run`, and counts its sine. Looks
	/// read into the tile's margin, so a ridge just past the tile's edge still counts there; give
	/// the tile a margin of at least `radius`.
	static func compute(tile: ElevationTile, metersPerSample: Double, radius: Int) -> [UInt8] {
		struct Step {
			let dx: Int
			let dy: Int
			let inverseRun: Float
		}
		let distances = steps(radius: radius)
		let looks: [[Step]] = (0..<directions).map { index in
			let angle = 2 * Double.pi * Double(index) / Double(directions)
			return distances.map { distance in
				Step(dx: Int((cos(angle) * Double(distance)).rounded()), dy: Int((sin(angle) * Double(distance)).rounded()),
					 inverseRun: Float(1 / (Double(distance) * metersPerSample)))
			}
		}
		let size = tile.size
		let grid = tile.gridSize
		let margin = tile.margin
		let share = 255 / Float(directions)
		var result = [UInt8](repeating: 0, count: size * size)
		tile.elevations.withUnsafeBufferPointer { elevations in
			for y in 0..<size {
				for x in 0..<size {
					let gx = x + margin, gy = y + margin
					let base = elevations[gy * grid + gx]
					var sum: Float = 0
					for look in looks {
						var steepest: Float = 0
						for step in look {
							let sx = gx + step.dx, sy = gy + step.dy
							guard sx >= 0, sx < grid, sy >= 0, sy < grid else { break }
							steepest = max(steepest, (elevations[sy * grid + sx] - base) * step.inverseRun)
						}
						sum += steepest / (1 + steepest * steepest).squareRoot()
					}
					result[y * size + x] = UInt8(min(255, (sum * share).rounded()))
				}
			}
		}
		return result
	}
}
