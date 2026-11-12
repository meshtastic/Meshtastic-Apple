//
//  LookoutCoast.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import Foundation

/// What a cinema room with real terrain out its windows stands on: a summit, for the fire lookout
/// and the castle tower, a headland on the coast, for the lighthouse, the roof of one of the
/// tallest buildings, for the city rooftop, or the face of one, for the sky deck hung off it.
enum LookoutSiteKind: String, Sendable, CaseIterable {
	case summit
	case coast
	case rooftop
	case skyDeck

	/// How far the room's floor stands above the ground: the lookout's tower, or the lighthouse's.
	/// A rooftop or a sky deck stands on its building, whose height each site carries, so it has
	/// none of its own.
	var standHeight: Double {
		switch self {
		case .summit: 34
		case .coast: 24
		case .rooftop, .skyDeck: 0
		}
	}

	/// Where the cinema keeps the site chosen.
	var siteKey: String {
		switch self {
		case .summit: "cinemaLookoutSite"
		case .coast: "cinemaLighthouseSite"
		case .rooftop: "cinemaRooftopSite"
		case .skyDeck: SpatialSkyDeck.siteKey
		}
	}

	/// Where the cinema keeps how many sixteenth turns clockwise the room is turned.
	var turnsKey: String {
		switch self {
		case .summit: SpatialLookout.turnsKey
		case .coast: "cinemaLighthouseSixteenthTurns"
		case .rooftop: "cinemaRooftopSixteenthTurns"
		case .skyDeck: "cinemaSkyDeckSixteenthTurns"
		}
	}

	/// The file the sites found are kept in, each kind in its own so moving between environments
	/// keeps every list.
	var cacheFileName: String {
		switch self {
		case .summit: "LookoutSites.json"
		case .coast: "LighthouseSites.json"
		case .rooftop: "RooftopSites.json"
		case .skyDeck: "SkyDeckSites.json"
		}
	}
}

/// Finds where a lighthouse could stand: land at the water's edge that looks out over open sea.
/// Works on a coarse grid of the highest ground in each cell, where the sea is the cells at or
/// below 0 m (the elevation tiles carry the sea floor, which the grid reads as 0). Outside the
/// visionOS-only code so it can be tested.
enum LookoutCoast {
	/// A cell a lighthouse could stand in.
	struct Candidate: Equatable {
		/// The cell, row-major from the north-west corner.
		let index: Int
		/// The highest ground in it, meters.
		let elevation: Float
		/// How many of `bearings` directions look out over open water.
		let openBearings: Int
		/// The true bearing, degrees, of the middle of the widest stretch of open water.
		let facing: Double

		/// Open water first, and a high headland over a low spit.
		var score: Float {
			Float(openBearings) + min(elevation, 100) / 25
		}
	}

	/// The directions looked along from each cell, evenly round.
	static let bearings = 32
	/// How far out along each direction the water has to reach, meters.
	static let reach = 6_000.0
	/// The share of a direction's covered cells that have to be sea for it to count as open water.
	static let openShare = 0.9
	/// The least open water a candidate must look out on, in directions.
	static let leastOpen = 4
	/// How many cells from the sea a candidate may be.
	static let shoreCells = 2

	/// A coarse grid over the terrain.
	struct Grid {
		/// The highest ground in each cell, row-major from the north-west corner.
		let heights: [Float]
		/// Whether the terrain has each cell at all.
		let covered: [Bool]
		let columns: Int
		let rows: Int
		/// A cell's width east to west, meters.
		let cellWidth: Double
		/// A cell's height north to south, meters.
		let cellHeight: Double
	}

	/// The land cells near the sea that look out over open water, best first.
	static func candidates(in grid: Grid) -> [Candidate] {
		let (heights, covered, columns, rows, cellWidth, cellHeight) = (grid.heights, grid.covered, grid.columns, grid.rows, grid.cellWidth, grid.cellHeight)
		guard columns > 0, rows > 0, heights.count == columns * rows, covered.count == heights.count else { return [] }
		func isSea(_ column: Int, _ row: Int) -> Bool? {
			guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
			let index = row * columns + column
			return covered[index] ? heights[index] <= 0 : nil
		}
		let step = min(cellWidth, cellHeight)
		let samples = max(2, Int(reach / step))
		// Each direction's walk, as cell offsets out to `reach`.
		let walks: [[(Int, Int)]] = (0..<bearings).map { b in
			let angle = Double(b) / Double(bearings) * 2 * .pi
			return (1...samples).map { k in
				let distance = Double(k) * step
				// East is +column; north is -row.
				return (Int((sin(angle) * distance / cellWidth).rounded()), Int((-cos(angle) * distance / cellHeight).rounded()))
			}
		}
		var found: [Candidate] = []
		for row in 0..<rows {
			for column in 0..<columns {
				let index = row * columns + column
				guard covered[index], heights[index] > 0, nearSea(column, row, isSea: isSea) else { continue }
				let open = walks.map { walk -> Bool in
					var seen = 0
					var sea = 0
					for (dx, dy) in walk {
						guard let water = isSea(column + dx, row + dy) else { continue }
						seen += 1
						if water { sea += 1 }
					}
					// Half the walk at least has to be in the terrain, or it says nothing.
					return seen * 2 >= walk.count && Double(sea) >= openShare * Double(seen)
				}
				let count = open.filter { $0 }.count
				guard count >= leastOpen else { continue }
				found.append(Candidate(index: index, elevation: heights[index], openBearings: count, facing: facing(open)))
			}
		}
		return found.sorted { $0.score > $1.score }
	}

	/// Whether a sea cell is within `shoreCells` of the cell.
	private static func nearSea(_ column: Int, _ row: Int, isSea: (Int, Int) -> Bool?) -> Bool {
		for dy in -shoreCells...shoreCells {
			for dx in -shoreCells...shoreCells where dx != 0 || dy != 0 {
				if isSea(column + dx, row + dy) == true { return true }
			}
		}
		return false
	}

	/// The true bearing of the middle of the longest run of open directions, going round past
	/// north. North when every direction is open.
	static func facing(_ open: [Bool]) -> Double {
		let count = open.count
		guard count > 0, open.contains(true) else { return 0 }
		guard open.contains(false) else { return 0 }
		// Start just after a closed direction, so no run is split across the end of the list.
		let start = (open.firstIndex(of: false)! + 1) % count
		var best = (start: 0, length: 0)
		var run = (start: 0, length: 0)
		for offset in 0..<count {
			let index = (start + offset) % count
			if open[index] {
				if run.length == 0 { run.start = index }
				run.length += 1
				if run.length > best.length { best = run }
			} else {
				run.length = 0
			}
		}
		let middle = Double(best.start) + Double(best.length - 1) / 2
		return (middle / Double(count) * 360).truncatingRemainder(dividingBy: 360)
	}
}
