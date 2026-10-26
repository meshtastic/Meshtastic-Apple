//
//  CoverageBands.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
//  Traces a coverage grid's signal bands as smooth polygons: marching squares
//  outlines at each band's floor, interpolated between samples, then lightly
//  smoothed and simplified. Each band is the area between its floor and the
//  next band's floor, so the bands tile the disc without overlapping.
//

import Foundation

extension CoverageGrid {
	/// A closed ring as `[lon, lat]` positions, first and last equal.
	typealias Ring = [[Double]]
	/// An outer ring followed by its holes.
	typealias Polygon = [Ring]

	/// Chaikin passes over each outline.
	static let smoothingPasses = 2
	/// Douglas-Peucker tolerance, in grid cells. A small closed outline uses a tenth of its size instead.
	static let simplifyToleranceCells = 0.1
	/// Outlines enclosing less than this, in square grid cells, are dropped.
	static let minRingAreaCells = 0.01
	/// The disc edge keeps about one point per this many degrees of bearing.
	static let discEdgeStepDegrees = 1.0

	/// The bands between successive `floors`, ascending; the last band is open-ended. Each band is a list of
	/// polygons with outer rings counterclockwise and holes clockwise, as GeoJSON wants.
	func bandPolygons(floors: [Double]) -> [[Polygon]] {
		var tracer = BandTracer(grid: self)
		let traced = floors.map { tracer.trace(level: $0) }
		// Pin every point where an outline leaves the disc edge, at every level, so outlines that share a stretch
		// of the edge keep the same points along it.
		for outline in traced.joined() { tracer.pinEndsOfDiscStretches(outline) }
		let outlines = traced.map { $0.compactMap(tracer.smooth) }
		return floors.indices.map { index in
			let above = index + 1 < outlines.count ? outlines[index + 1].map { $0.reversed() } : []
			return tracer.assemble(outlines[index] + above).map { polygon in polygon.map(tracer.coordinates) }
		}
	}
}

/// A point in grid units: x is the column and y is minus the row, so north is up and counterclockwise is positive.
private struct GridPoint {
	var x: Double
	var y: Double

	func distanceSquared(to other: GridPoint) -> Double {
		(x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)
	}
}

/// One closed outline, without the repeated closing point. Points on the disc edge are marked so every
/// level keeps them identical and the bands meet there exactly.
private struct Outline {
	var points: [GridPoint]
	var onDiscEdge: [Bool]
	/// The grid edge each traced point crosses; empty once smoothed.
	var edges: [Int] = []

	/// Shoelace area; positive when counterclockwise.
	var signedArea: Double {
		var sum = 0.0
		for index in points.indices {
			let a = points[index]
			let b = points[(index + 1) % points.count]
			sum += a.x * b.y - b.x * a.y
		}
		return sum / 2
	}

	/// Every point on the disc edge: the ring is the whole disc.
	var isWholeDisc: Bool { onDiscEdge.allSatisfy { $0 } }

	func reversed() -> Outline {
		Outline(points: points.reversed(), onDiscEdge: onDiscEdge.reversed(), edges: edges.reversed())
	}

	func contains(_ point: GridPoint) -> Bool {
		var inside = false
		var j = points.count - 1
		for i in points.indices {
			let a = points[i]
			let b = points[j]
			if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
				inside.toggle()
			}
			j = i
		}
		return inside
	}
}

private struct BandTracer {
	let grid: CoverageGrid
	/// The grid padded with one row and column of empty samples on every side, so every outline closes.
	let paddedWidth: Int
	let paddedHeight: Int
	/// Where the disc edge crosses each edge between a sample and an empty one, as a fraction from the edge's
	/// first node, and whether to keep that point when thinning the disc edge. Indexed by edge id.
	let discFraction: [Double?]
	var keepOnDiscEdge: [Bool]

	init(grid: CoverageGrid) {
		self.grid = grid
		let paddedWidth = grid.width + 2
		let paddedHeight = grid.height + 2
		self.paddedWidth = paddedWidth
		self.paddedHeight = paddedHeight
		let edgeCount = paddedWidth * paddedHeight * 2
		var fractions = [Double?](repeating: nil, count: edgeCount)
		var keep = [Bool](repeating: false, count: edgeCount)
		var firstInBin: [Int: (angle: Double, edge: Int)] = [:]
		let centerX = Double(grid.width - 1) / 2
		let centerY = -Double(grid.height - 1) / 2
		func distanceKm(_ node: Int) -> Double {
			let column = Double(node % paddedWidth - 1)
			let row = Double(node / paddedWidth - 1)
			return LocalCoverage.haversineKm(grid.site.latitude, grid.site.longitude, grid.latitude(atRow: row), grid.longitude(atColumn: column))
		}
		for node in 0..<(paddedWidth * paddedHeight) {
			for vertical in [false, true] {
				let other = vertical ? node + paddedWidth : node + 1
				guard vertical ? node / paddedWidth + 1 < paddedHeight : node % paddedWidth + 1 < paddedWidth else { continue }
				let a = Self.value(grid, node, paddedWidth)
				let b = Self.value(grid, other, paddedWidth)
				guard a.isNaN != b.isNaN else { continue }
				let edge = node * 2 + (vertical ? 1 : 0)
				// Interpolate distance from the site so the disc edge is round. A gap that isn't the disc's
				// (an empty sample inside it) stores nothing and gets the midpoint when traced.
				let da = distanceKm(node)
				let db = distanceKm(other)
				let fraction = (grid.site.radiusKm - da) / (db - da)
				guard da != db, fraction >= 0, fraction <= 1 else { continue }
				fractions[edge] = fraction
				let point = Self.point(edge: edge, fraction: fraction, paddedWidth: paddedWidth)
				var angle = atan2(point.y - centerY, point.x - centerX) * 180 / .pi
				if angle < 0 { angle += 360 }
				let bin = Int(angle / CoverageGrid.discEdgeStepDegrees)
				if let current = firstInBin[bin], current.angle <= angle { continue }
				firstInBin[bin] = (angle, edge)
			}
		}
		for entry in firstInBin.values { keep[entry.edge] = true }
		discFraction = fractions
		keepOnDiscEdge = keep
	}

	private static func value(_ grid: CoverageGrid, _ node: Int, _ paddedWidth: Int) -> Double {
		let x = node % paddedWidth - 1
		let y = node / paddedWidth - 1
		guard x >= 0, y >= 0, x < grid.width, y < grid.height else { return .nan }
		return grid.at(x, y)
	}

	/// Edge `id` runs from node `id / 2` right (even) or down (odd). Samples sit on nodes.
	private static func point(edge: Int, fraction: Double, paddedWidth: Int) -> GridPoint {
		let node = edge / 2
		let column = Double(node % paddedWidth - 1)
		let row = Double(node / paddedWidth - 1)
		return edge % 2 == 0 ? GridPoint(x: column + fraction, y: -row) : GridPoint(x: column, y: -(row + fraction))
	}

	private func value(_ node: Int) -> Double { Self.value(grid, node, paddedWidth) }

	// MARK: - Tracing

	/// Outlines of the area at or above `level`, outer rings counterclockwise and holes clockwise, with
	/// specks under `minRingAreaCells` left out.
	func trace(level: Double) -> [Outline] {
		let nodes = paddedWidth * paddedHeight
		var inside = [Bool](repeating: false, count: nodes)
		for node in 0..<nodes {
			let sample = value(node)
			inside[node] = !sample.isNaN && sample >= level
		}
		// next[edge] is the edge where the outline leaving `edge` arrives, keeping the inside on its left.
		var next = [Int](repeating: -1, count: nodes * 2)
		for row in 0..<(paddedHeight - 1) {
			for column in 0..<(paddedWidth - 1) {
				let topLeft = row * paddedWidth + column
				let first = inside[topLeft]
				if inside[topLeft + 1] == first, inside[topLeft + paddedWidth] == first, inside[topLeft + paddedWidth + 1] == first { continue }
				let corners = [topLeft, topLeft + 1, topLeft + paddedWidth + 1, topLeft + paddedWidth]
				let state = corners.map { inside[$0] }
				// Edges clockwise: top, right, bottom, left.
				let edges = [topLeft * 2, (topLeft + 1) * 2 + 1, (topLeft + paddedWidth) * 2, topLeft * 2 + 1]
				var entering: [Int] = []
				var exiting: [Int] = []
				for side in 0..<4 where state[side] != state[(side + 1) % 4] {
					if state[(side + 1) % 4] { entering.append(side) } else { exiting.append(side) }
				}
				if entering.count == 1 {
					next[edges[entering[0]]] = edges[exiting[0]]
					continue
				}
				// A saddle: the cell's mean decides whether the two inside corners join. Any empty corner keeps them apart.
				let samples = corners.map(value)
				let mean = samples.reduce(0, +) / 4
				let joined = !mean.isNaN && mean >= level
				for side in entering {
					let partner = joined ? (side + 3) % 4 : (side + 1) % 4
					next[edges[side]] = edges[partner]
				}
			}
		}

		var outlines: [Outline] = []
		for start in next.indices where next[start] >= 0 {
			var points: [GridPoint] = []
			var onEdge: [Bool] = []
			var edges: [Int] = []
			var edge = start
			while next[edge] >= 0 {
				let (point, isDisc) = crossing(edge: edge, level: level)
				points.append(point)
				onEdge.append(isDisc)
				edges.append(edge)
				let following = next[edge]
				next[edge] = -1
				edge = following
			}
			let outline = Outline(points: points, onDiscEdge: onEdge, edges: edges)
			if points.count >= 3, abs(outline.signedArea) >= CoverageGrid.minRingAreaCells { outlines.append(outline) }
		}
		return outlines
	}

	private func crossing(edge: Int, level: Double) -> (GridPoint, Bool) {
		if let fraction = discFraction[edge] {
			return (Self.point(edge: edge, fraction: fraction, paddedWidth: paddedWidth), true)
		}
		let node = edge / 2
		let a = value(node)
		let b = value(edge % 2 == 0 ? node + 1 : node + paddedWidth)
		var fraction = 0.5
		if !a.isNaN, !b.isNaN, a != b {
			// Kept off the nodes so neighboring crossings never coincide.
			fraction = min(max((level - a) / (b - a), 0.01), 0.99)
		}
		return (Self.point(edge: edge, fraction: fraction, paddedWidth: paddedWidth), false)
	}

	// MARK: - Smoothing

	/// Keeps the disc edge points where `outline` leaves or joins the edge, whichever level it was traced at.
	mutating func pinEndsOfDiscStretches(_ outline: Outline) {
		let count = outline.points.count
		for index in 0..<count where outline.onDiscEdge[index] {
			if !outline.onDiscEdge[(index + count - 1) % count] || !outline.onDiscEdge[(index + 1) % count] {
				keepOnDiscEdge[outline.edges[index]] = true
			}
		}
	}

	/// Smooths and simplifies the stretches between disc edge points, and thins the disc edge to fixed
	/// bearings, so an outline shared by two bands comes out the same in both.
	func smooth(_ outline: Outline) -> Outline? {
		let count = outline.points.count
		guard let firstDisc = outline.onDiscEdge.firstIndex(of: true) else {
			let xs = outline.points.map(\.x)
			let ys = outline.points.map(\.y)
			let size = hypot(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
			let tolerance = min(CoverageGrid.simplifyToleranceCells, size / 10)
			var points = simplifyClosed(chaikin(outline.points, closed: true), tolerance: tolerance)
			// A speck simplified to a few corners would read as a square again; one pass gives it eight.
			if points.count < 6 { points = chaikin(outline.points, closed: true, passes: 1) }
			return points.count >= 3 ? Outline(points: points, onDiscEdge: [Bool](repeating: false, count: points.count)) : nil
		}
		// Rotate to start on the disc edge, then walk it as stretches between disc points.
		let points = Array(outline.points[firstDisc...] + outline.points[..<firstDisc])
		let onEdge = Array(outline.onDiscEdge[firstDisc...] + outline.onDiscEdge[..<firstDisc])
		let edges = Array(outline.edges[firstDisc...] + outline.edges[..<firstDisc])
		var outPoints: [GridPoint] = []
		var outFlags: [Bool] = []
		var index = 0
		while index < count {
			if onEdge[index] {
				if keepOnDiscEdge[edges[index]] {
					outPoints.append(points[index])
					outFlags.append(true)
				}
				index += 1
				continue
			}
			// A stretch of interior points between two disc points, which stay put.
			var end = index
			while !onEdge[end % count] { end += 1 }
			let run = [points[index - 1]] + points[index..<end] + [points[end % count]]
			let smoothed = simplifyOpen(chaikin(run, closed: false), tolerance: CoverageGrid.simplifyToleranceCells)
			let interior = smoothed.dropFirst().dropLast()
			outPoints.append(contentsOf: interior)
			outFlags.append(contentsOf: [Bool](repeating: false, count: interior.count))
			index = end
		}
		return outPoints.count >= 3 ? Outline(points: outPoints, onDiscEdge: outFlags) : nil
	}

	private func chaikin(_ points: [GridPoint], closed: Bool, passes: Int = CoverageGrid.smoothingPasses) -> [GridPoint] {
		var current = points
		for _ in 0..<passes {
			guard current.count >= 3 else { return current }
			var out: [GridPoint] = []
			let segments = closed ? current.count : current.count - 1
			if !closed { out.append(current[0]) }
			for index in 0..<segments {
				let a = current[index]
				let b = current[(index + 1) % current.count]
				out.append(GridPoint(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
				out.append(GridPoint(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
			}
			if !closed { out.append(current[current.count - 1]) }
			current = out
		}
		return current
	}

	/// Douglas-Peucker with both ends kept.
	private func simplifyOpen(_ points: [GridPoint], tolerance: Double) -> [GridPoint] {
		guard points.count > 2 else { return points }
		var keep = [Bool](repeating: false, count: points.count)
		keep[0] = true
		keep[points.count - 1] = true
		var stack = [(0, points.count - 1)]
		while let (first, last) = stack.popLast() {
			guard last > first + 1 else { continue }
			var farthest = first
			var distance = 0.0
			for index in (first + 1)..<last {
				let d = Self.distance(points[index], from: points[first], to: points[last])
				if d > distance { distance = d; farthest = index }
			}
			if distance > tolerance {
				keep[farthest] = true
				stack.append((first, farthest))
				stack.append((farthest, last))
			}
		}
		return points.indices.filter { keep[$0] }.map { points[$0] }
	}

	/// Douglas-Peucker on a closed ring, split at the point farthest from the first.
	private func simplifyClosed(_ points: [GridPoint], tolerance: Double) -> [GridPoint] {
		guard points.count > 3 else { return points }
		let first = points[0]
		let far = points.indices.max { hypot(points[$0].x - first.x, points[$0].y - first.y) < hypot(points[$1].x - first.x, points[$1].y - first.y) } ?? 0
		let one = simplifyOpen(Array(points[0...far]), tolerance: tolerance)
		let two = simplifyOpen(Array(points[far...]) + [first], tolerance: tolerance)
		return one + two.dropFirst().dropLast()
	}

	private static func distance(_ point: GridPoint, from a: GridPoint, to b: GridPoint) -> Double {
		let dx = b.x - a.x
		let dy = b.y - a.y
		let length = hypot(dx, dy)
		guard length > 0 else { return hypot(point.x - a.x, point.y - a.y) }
		return abs(dx * (a.y - point.y) - dy * (a.x - point.x)) / length
	}

	// MARK: - Assembly

	/// Groups outlines into polygons: each hole goes to the smallest outer ring holding it.
	func assemble(_ outlines: [Outline]) -> [[Outline]] {
		let areas = outlines.map(\.signedArea)
		let outers = outlines.indices.filter { areas[$0] > 0 }
		var holes: [Int: [Outline]] = [:]
		var cancelled = Set<Int>()
		for index in outlines.indices where areas[index] < 0 {
			let hole = outlines[index]
			// Test with the hole's point farthest from the disc edge, where the outline holding it can't pass close by.
			let center = GridPoint(x: Double(grid.width - 1) / 2, y: -Double(grid.height - 1) / 2)
			let probe = hole.points.indices
				.filter { !hole.onDiscEdge[$0] }
				.min { hole.points[$0].distanceSquared(to: center) < hole.points[$1].distanceSquared(to: center) }
				.map { hole.points[$0] }
			guard let probe else {
				// A hole made only of disc edge points is the whole disc at the level above. The outer made only of
				// disc edge points at this level is the same ring, so the band between them is empty.
				if let twin = outers.first(where: { !cancelled.contains($0) && outlines[$0].isWholeDisc }) {
					cancelled.insert(twin)
				}
				continue
			}
			let holder = outers
				.filter { !cancelled.contains($0) && areas[$0] > -areas[index] && outlines[$0].contains(probe) }
				.min { areas[$0] < areas[$1] }
			if let holder { holes[holder, default: []].append(hole) }
		}
		return outers.filter { !cancelled.contains($0) }.map { [outlines[$0]] + (holes[$0] ?? []) }
	}

	/// Closed `[lon, lat]` positions.
	func coordinates(_ outline: Outline) -> CoverageGrid.Ring {
		var ring = outline.points.map { [grid.longitude(atColumn: $0.x), grid.latitude(atRow: -$0.y)] }
		ring.append(ring[0])
		return ring
	}
}
