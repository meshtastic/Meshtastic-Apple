//
//  ContourGenerator.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/15/26.
//
//  Marching-squares contour extraction from decoded elevation tiles.
//  Pure geometry: no rendering, no I/O. See
//  specs/018-offline-terrain-layer/data-model.md (ContourIntervalTable).
//

import Foundation
import CoreGraphics

/// One contour polyline for a single elevation level, in tile-unit
/// coordinates: (0, 0) is the tile's top-left corner, (1, 1) the bottom-right.
/// Points may run slightly outside [0, 1] into the margin ring so lines meet
/// across tile boundaries. Closed rings repeat the first point at the end.
struct ContourLine: Sendable {
	/// Contour elevation in meters.
	let elevation: Double
	/// True when this level falls on the index interval (drawn heavier, labeled).
	let isIndex: Bool
	/// Polyline vertices in tile units. Closed when `points.first == points.last`.
	let points: [CGPoint]
}

/// Contour spacing for one zoom band, always expressed in meters. The metric
/// flag picks which family of round numbers the meters encode (100 m vs 500 ft).
struct ContourIntervals: Sendable {
	/// Spacing between adjacent contour lines, meters.
	let minor: Double
	/// Spacing between index (heavy) contours, meters. A multiple of `minor`.
	let index: Double

	/// Zoom → interval table from the feature spec. Imperial values are round
	/// feet expressed in meters (1 ft = 0.3048 m).
	static func intervals(forZoom zoom: Int, metric: Bool) -> ContourIntervals {
		let foot = 0.3048
		switch zoom {
		case ...10:
			return metric
				? ContourIntervals(minor: 500, index: 2500)
				: ContourIntervals(minor: 2000 * foot, index: 10000 * foot)
		case 11...12:
			return metric
				? ContourIntervals(minor: 100, index: 500)
				: ContourIntervals(minor: 500 * foot, index: 2500 * foot)
		case 13...14:
			return metric
				? ContourIntervals(minor: 50, index: 250)
				: ContourIntervals(minor: 200 * foot, index: 1000 * foot)
		default:
			return metric
				? ContourIntervals(minor: 20, index: 100)
				: ContourIntervals(minor: 100 * foot, index: 500 * foot)
		}
	}
}

/// Extracts contour polylines from an `ElevationTile` with marching squares.
/// The march covers the margin ring so segments continue across tile edges,
/// and levels are every multiple of `intervals.minor` inside the tile's
/// elevation range (positive levels only — the data includes bathymetry
/// banding). Saddle cells are disambiguated by the cell-center average.
enum ContourGenerator {

	private typealias GridPoint = SIMD2<Double>

	private struct Segment {
		var a: GridPoint
		var b: GridPoint
	}

	/// Endpoint identity for chaining. Matching endpoints from adjacent cells
	/// are computed from the same two samples and are bit-identical; the 2^-20
	/// grid-unit quantization only mops up degenerate corner touches.
	private struct PointKey: Hashable {
		var x: Int64
		var y: Int64

		init(_ point: GridPoint) {
			x = Int64((point.x * 1_048_576).rounded())
			y = Int64((point.y * 1_048_576).rounded())
		}
	}

	static func contours(tile: ElevationTile, intervals: ContourIntervals) -> [ContourLine] {
		let gridSize = tile.gridSize
		guard gridSize >= 2, tile.size > 0, intervals.minor > 0 else { return [] }
		let elevations = tile.elevations
		guard elevations.count == gridSize * gridSize else { return [] }

		var minElevation = Double.greatestFiniteMagnitude
		var maxElevation = -Double.greatestFiniteMagnitude
		for value in elevations {
			let elevation = Double(value)
			if elevation < minElevation { minElevation = elevation }
			if elevation > maxElevation { maxElevation = elevation }
		}
		guard maxElevation > minElevation else { return [] }

		let minor = intervals.minor
		// Every multiple of `minor` in range. Positive levels only: the elevation
		// data carries ocean bathymetry, and sub-sea-level contours would draw
		// rings on open water.
		let firstLevelIndex = max(Int((max(minElevation, 0) / minor).rounded(.up)), 1)
		let lastLevelIndex = Int((maxElevation / minor).rounded(.down))
		guard firstLevelIndex <= lastLevelIndex else { return [] }
		let levelCount = lastLevelIndex - firstLevelIndex + 1

		var levelSegments = [[Segment]](repeating: [], count: levelCount)

		let margin = tile.margin
		// Cell-major march: each cell visits only the levels that cross it, so
		// the whole grid is scanned once regardless of the level count.
		for rawY in 0..<(gridSize - 1) {
			let rowBase = rawY * gridSize
			let y = Double(rawY - margin)
			for rawX in 0..<(gridSize - 1) {
				let base = rowBase + rawX
				let topLeft = Double(elevations[base])
				let topRight = Double(elevations[base + 1])
				let bottomLeft = Double(elevations[base + gridSize])
				let bottomRight = Double(elevations[base + gridSize + 1])

				let low = min(min(topLeft, topRight), min(bottomLeft, bottomRight))
				let high = max(max(topLeft, topRight), max(bottomLeft, bottomRight))
				if high == low { continue }

				var levelIndex = max(Int((low / minor).rounded(.up)), firstLevelIndex)
				let lastCellLevel = min(Int((high / minor).rounded(.down)), lastLevelIndex)
				if levelIndex > lastCellLevel { continue }

				let x = Double(rawX - margin)
				while levelIndex <= lastCellLevel {
					let level = Double(levelIndex) * minor
					// A corner is "above" only when strictly greater, so a
					// straddling edge always has distinct endpoint values and
					// interpolation never divides by zero.
					var code = 0
					if topLeft > level { code |= 1 }
					if topRight > level { code |= 2 }
					if bottomRight > level { code |= 4 }
					if bottomLeft > level { code |= 8 }
					if code != 0 && code != 15 {
						func top() -> GridPoint { GridPoint(x + (level - topLeft) / (topRight - topLeft), y) }
						func right() -> GridPoint { GridPoint(x + 1, y + (level - topRight) / (bottomRight - topRight)) }
						func bottom() -> GridPoint { GridPoint(x + (level - bottomLeft) / (bottomRight - bottomLeft), y + 1) }
						func left() -> GridPoint { GridPoint(x, y + (level - topLeft) / (bottomLeft - topLeft)) }
						func emit(_ a: GridPoint, _ b: GridPoint) {
							guard PointKey(a) != PointKey(b) else { return }
							levelSegments[levelIndex - firstLevelIndex].append(Segment(a: a, b: b))
						}

						switch code {
						case 1, 14: emit(left(), top())
						case 2, 13: emit(top(), right())
						case 3, 12: emit(left(), right())
						case 4, 11: emit(right(), bottom())
						case 6, 9: emit(top(), bottom())
						case 7, 8: emit(left(), bottom())
						case 5:
							// Saddle: the cell-center average decides whether
							// the two "above" corners join through the middle.
							if (topLeft + topRight + bottomRight + bottomLeft) * 0.25 > level {
								emit(top(), right())
								emit(left(), bottom())
							} else {
								emit(left(), top())
								emit(right(), bottom())
							}
						case 10:
							if (topLeft + topRight + bottomRight + bottomLeft) * 0.25 > level {
								emit(left(), top())
								emit(right(), bottom())
							} else {
								emit(top(), right())
								emit(left(), bottom())
							}
						default:
							break
						}
					}
					levelIndex += 1
				}
			}
		}

		let size = Double(tile.size)
		var result: [ContourLine] = []
		for (offset, segments) in levelSegments.enumerated() where !segments.isEmpty {
			let level = Double(firstLevelIndex + offset) * minor
			let indexMultiple = (level / intervals.index).rounded() * intervals.index
			let isIndex = abs(level - indexMultiple) < 0.01
			for chain in chained(segments) where chain.count >= 2 {
				let points = chain.map { CGPoint(x: $0.x / size, y: $0.y / size) }
				result.append(ContourLine(elevation: level, isIndex: isIndex, points: points))
			}
		}
		return result
	}

	/// Joins segments that share endpoints (exact after quantization) into
	/// polylines: grow forward from an unused segment until the chain closes or
	/// stalls, then reverse once and grow the other end.
	private static func chained(_ segments: [Segment]) -> [[GridPoint]] {
		var adjacency = [PointKey: [Int]](minimumCapacity: segments.count * 2)
		for (index, segment) in segments.enumerated() {
			adjacency[PointKey(segment.a), default: []].append(index)
			adjacency[PointKey(segment.b), default: []].append(index)
		}

		var used = [Bool](repeating: false, count: segments.count)
		var polylines: [[GridPoint]] = []

		func takeNext(at key: PointKey) -> GridPoint? {
			guard let candidates = adjacency[key] else { return nil }
			for index in candidates where !used[index] {
				used[index] = true
				let segment = segments[index]
				return PointKey(segment.a) == key ? segment.b : segment.a
			}
			return nil
		}

		for index in 0..<segments.count where !used[index] {
			used[index] = true
			var chain: [GridPoint] = [segments[index].a, segments[index].b]
			let startKey = PointKey(chain[0])
			var closed = false
			while let next = takeNext(at: PointKey(chain[chain.count - 1])) {
				if PointKey(next) == startKey {
					chain.append(chain[0]) // close exactly: first == last
					closed = true
					break
				}
				chain.append(next)
			}
			if !closed {
				chain.reverse()
				while let next = takeNext(at: PointKey(chain[chain.count - 1])) {
					chain.append(next)
				}
			}
			polylines.append(chain)
		}
		return polylines
	}
}
