//
//  SpatialTerrainContours.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import CoreGraphics
import CoreLocation
import CoreText
import UIKit

/// Contour lines for the spatial map texture, generated from the downloaded terrain with the same
/// marching squares as the 2D map and stroked in the 2D map's colors. Index lines carry their
/// elevation now and then, set along the line in a gap, the way a printed topographic map does.
enum SpatialTerrainContours {

	/// The contour lines of one elevation tile, as map coordinates. `clip` is the part of the box
	/// this tile owns (its bounds within the download), so lines that run into a neighbor's margin
	/// are not drawn twice.
	struct Tile: Sendable {
		let clip: GeoBounds
		let minor: [[CLLocationCoordinate2D]]
		let index: [IndexLine]
	}

	/// An index line and the elevation it follows, in meters.
	struct IndexLine: Sendable {
		let elevation: Double
		let coordinates: [CLLocationCoordinate2D]
	}

	/// An elevation printed on an index line: its center on the texture (y up), the direction the
	/// line runs there, and the text's size.
	struct Label: Equatable {
		let text: String
		let center: CGPoint
		let angle: CGFloat
		let size: CGSize

		/// The corners of the text's box, turned along the line, grown by `margin` all round.
		func corners(margin: CGFloat = 0) -> [CGPoint] {
			let halfWidth = size.width / 2 + margin, halfHeight = size.height / 2 + margin
			let along = CGPoint(x: cos(angle), y: sin(angle)), across = CGPoint(x: -sin(angle), y: cos(angle))
			return [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { (x: CGFloat, y: CGFloat) in
				CGPoint(x: center.x + x * halfWidth * along.x + y * halfHeight * across.x,
						y: center.y + x * halfWidth * along.y + y * halfHeight * across.y)
			}
		}
	}

	/// The terrain mesh's heights, for thinning lines where the texture is stretched over steep
	/// ground. Rows run north to south and columns west to east, evenly in latitude and longitude.
	struct Relief {
		let bounds: GeoBounds
		let columns: Int
		let rows: Int
		/// Row-major heights in model units.
		let heights: [Float]
		/// The ground spacing between columns and between rows, in model units.
		let cellWidth: Float
		let cellDepth: Float

		init(bounds: GeoBounds, columns: Int, rows: Int, heights: [Float], cellWidth: Float, cellDepth: Float) {
			self.bounds = bounds
			self.columns = columns
			self.rows = rows
			self.heights = heights
			self.cellWidth = cellWidth
			self.cellDepth = cellDepth
		}

		init(geometry: SpatialTerrainGeometry) {
			let transform = geometry.transform
			self.init(
				bounds: transform.frame.bounds, columns: geometry.columns, rows: geometry.rows, heights: geometry.groundHeights,
				cellWidth: transform.footprint.x / Float(max(geometry.columns - 1, 1)),
				cellDepth: transform.footprint.y / Float(max(geometry.rows - 1, 1))
			)
		}

		/// How much narrower to draw a line at `coordinate`: the texture is laid straight down on the
		/// mesh, so on a slope one texel covers `sqrt(1 + slope²)` of ground, all of it across the
		/// contour line, which runs level. 1 on flat ground.
		func widthFactor(at coordinate: CLLocationCoordinate2D) -> CGFloat {
			guard columns >= 2, rows >= 2, cellWidth > 0, cellDepth > 0 else { return 1 }
			let u = (coordinate.longitude - bounds.minLon) / max(bounds.maxLon - bounds.minLon, 1e-12)
			let v = (bounds.maxLat - coordinate.latitude) / max(bounds.maxLat - bounds.minLat, 1e-12)
			let i = min(max(Int((min(max(u, 0), 1) * Double(columns - 1)).rounded()), 0), columns - 1)
			let j = min(max(Int((min(max(v, 0), 1) * Double(rows - 1)).rounded()), 0), rows - 1)
			let left = max(i - 1, 0), right = min(i + 1, columns - 1)
			let north = max(j - 1, 0), south = min(j + 1, rows - 1)
			let slopeX = (heights[j * columns + right] - heights[j * columns + left]) / (Float(right - left) * cellWidth)
			let slopeZ = (heights[south * columns + i] - heights[north * columns + i]) / (Float(south - north) * cellDepth)
			return CGFloat(1 / (1 + slopeX * slopeX + slopeZ * slopeZ).squareRoot())
		}
	}

	/// An index line on the texture, for placing labels.
	struct CanvasLine {
		let elevation: Double
		let points: [CGPoint]
		/// The part of the texture the line's tile owns; a label's center stays inside it.
		let clip: CGRect
	}

	/// Minor spacing → index spacing, finest first. Imperial values are round feet in meters.
	private static let metricLadder: [(minor: Double, index: Double)] = [
		(10, 50), (20, 100), (50, 250), (100, 500), (200, 1000), (500, 2500), (1000, 5000)
	]
	private static let imperialLadder: [(minor: Double, index: Double)] = [
		(20, 100), (40, 200), (100, 500), (200, 1000), (500, 2500), (1000, 5000), (2000, 10000)
	].map { ($0.0 * 0.3048, $0.1 * 0.3048) }

	/// The finest spacing that keeps the box's relief to at most `maxMinorLines` minor lines
	/// (about eight index lines), so steep ground stays readable on the texture.
	static func intervals(relief: Double, metric: Bool, maxMinorLines: Double = 40) -> ContourIntervals {
		let ladder = metric ? metricLadder : imperialLadder
		let step = ladder.first { relief / $0.minor <= maxMinorLines } ?? ladder[ladder.count - 1]
		return ContourIntervals(minor: step.minor, index: step.index)
	}

	/// Contours for the box from the downloaded terrain, read at a zoom where one tile is about
	/// 512 texels across, no finer than the data. Decoding tiles is most of the cost, and lines
	/// from one sample per two texels still read smoothly. Empty where nothing is downloaded.
	static func tiles(frame: SpatialFrame, width: Int, dataZoom: Int, intervals: ContourIntervals, source: any ElevationTileSource) async -> [Tile] {
		let bounds = frame.bounds
		let tileSize = TerrainStore.tileSize
		let lonSpan = max(bounds.maxLon - bounds.minLon, 1e-9)
		let wanted = Double(width) / Double(2 * tileSize) * 360 / lonSpan
		let zoom = min(max(Int(log2(wanted).rounded(.down)), 0), dataZoom)
		let northWest = TerrainStore.tilePixel(latitude: bounds.maxLat, longitude: bounds.minLon, z: zoom, size: tileSize)
		let southEast = TerrainStore.tilePixel(latitude: bounds.minLat, longitude: bounds.maxLon, z: zoom, size: tileSize)
		var result: [Tile] = []
		for y in northWest.y...southEast.y {
			for x in northWest.x...southEast.x {
				if Task.isCancelled { return [] }
				guard let coverage = await source.coverage(z: zoom, x: x, y: y),
					  let tile = await source.elevationTile(z: zoom, x: x, y: y, margin: 2) else { continue }
				let tileBounds = TerrainStore.tileBounds(z: zoom, x: x, y: y)
				let clip = GeoBounds(
					minLon: max(tileBounds.minLon, coverage.minLon), minLat: max(tileBounds.minLat, coverage.minLat),
					maxLon: min(tileBounds.maxLon, coverage.maxLon), maxLat: min(tileBounds.maxLat, coverage.maxLat)
				)
				guard clip.maxLon > clip.minLon, clip.maxLat > clip.minLat else { continue }
				var minor: [[CLLocationCoordinate2D]] = []
				var index: [IndexLine] = []
				for line in ContourGenerator.contours(tile: tile, intervals: intervals) where line.points.count >= 2 {
					let coordinates = line.coordinates(z: zoom, x: x, y: y)
					if line.isIndex {
						index.append(IndexLine(elevation: line.elevation, coordinates: coordinates))
					} else {
						minor.append(coordinates)
					}
				}
				if !minor.isEmpty || !index.isEmpty {
					result.append(Tile(clip: clip, minor: minor, index: index))
				}
			}
		}
		return result
	}

	/// Strokes the contours over the image: white over imagery, brown otherwise, index lines
	/// heavier, like the 2D map. Line widths scale with the image so they read the same at any size,
	/// and with `relief` they're drawn thinner on steep ground, where the texture is stretched, so
	/// they look as wide on a mountainside as on the flat. Index lines are labeled with their
	/// elevation in feet or meters, with no unit, as on a printed map, outlined like the map's
	/// place names so they read over the lines and the ground.
	static func draw(_ tiles: [Tile], over image: CGImage, frame: SpatialFrame, imagery: Bool, metric: Bool = true, dark: Bool = false, relief: Relief? = nil) -> CGImage? {
		let width = image.width, height = image.height
		guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
									  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
		let size = CGSize(width: width, height: height)
		context.draw(image, in: CGRect(origin: .zero, size: size))
		let scale = CGFloat(max(width, height)) / 2048
		let minorColor = imagery ? UIColor.white.withAlphaComponent(0.55) : UIColor.brown.withAlphaComponent(0.45)
		let indexColor = imagery ? UIColor.white.withAlphaComponent(0.9) : UIColor.brown.withAlphaComponent(0.8)
		context.setLineJoin(.round)
		context.setLineCap(.round)
		// The slab's sides stretch the texture's edge pixels downward, so lines touching the edge
		// would turn into stripes there. Keep a thin border clear.
		let border = CGRect(origin: .zero, size: size).insetBy(dx: max(2, 4 * scale), dy: max(2, 4 * scale))
		func canvas(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
			SpatialTextureRenderer.canvasPoint(coordinate, frame: frame, size: size)
		}
		func clipRect(_ tile: Tile) -> CGRect {
			let topLeft = canvas(CLLocationCoordinate2D(latitude: tile.clip.maxLat, longitude: tile.clip.minLon))
			let bottomRight = canvas(CLLocationCoordinate2D(latitude: tile.clip.minLat, longitude: tile.clip.maxLon))
			return CGRect(x: topLeft.x, y: bottomRight.y, width: bottomRight.x - topLeft.x, height: topLeft.y - bottomRight.y).intersection(border)
		}

		let font = UIFont.systemFont(ofSize: labelFontSize * scale, weight: .semibold)
		let canvasLines = tiles.flatMap { tile in
			let clip = clipRect(tile)
			return tile.index.map { CanvasLine(elevation: $0.elevation, points: $0.coordinates.map(canvas), clip: clip) }
		}
		let labels = placeLabels(on: canvasLines, metric: metric, scale: scale, within: border) { text in
			textLine(text, font: font, color: indexColor).size
		}
		// The lines stop short of each label, so the number sits in a gap in its line.
		let gaps = CGMutablePath()
		gaps.addRect(CGRect(origin: .zero, size: size))
		for label in labels {
			gaps.addLines(between: label.corners(margin: labelGap * scale))
			gaps.closeSubpath()
		}

		for tile in tiles {
			context.saveGState()
			context.clip(to: clipRect(tile))
			context.addPath(gaps)
			context.clip(using: .evenOdd)
			let lines = [(tile.minor, minorColor, max(1, 1.5 * scale)), (tile.index.map(\.coordinates), indexColor, max(2, 3 * scale))]
			for (lines, color, lineWidth) in lines where !lines.isEmpty {
				// Drawn opaque in a layer that's then laid on at the color's opacity, so crossings
				// and the joins between pieces of different widths don't darken.
				context.setAlpha(color.cgColor.alpha)
				context.beginTransparencyLayer(auxiliaryInfo: nil)
				context.setStrokeColor(color.withAlphaComponent(1).cgColor)
				for (width, path) in paths(lines, width: lineWidth, relief: relief, canvas: canvas) {
					context.addPath(path)
					context.setLineWidth(width)
					context.strokePath()
				}
				context.endTransparencyLayer()
				context.setAlpha(1)
			}
			context.restoreGState()
		}

		context.textMatrix = .identity
		let haloColor = SpatialOfflineLabels.haloColor(dark: dark || imagery)
		for label in labels {
			let line = textLine(label.text, font: font, color: indexColor.withAlphaComponent(1))
			let halo = textLine(label.text, font: font, color: .clear, halo: haloColor)
			context.saveGState()
			context.translateBy(x: label.center.x, y: label.center.y)
			context.rotate(by: label.angle)
			context.textPosition = CGPoint(x: -line.size.width / 2, y: -line.size.height / 2 + line.descent)
			CTLineDraw(halo.line, context)
			context.textPosition = CGPoint(x: -line.size.width / 2, y: -line.size.height / 2 + line.descent)
			CTLineDraw(line.line, context)
			context.restoreGState()
		}
		return context.makeImage()
	}

	/// The lines as one path per width. Without `relief` every piece is `width`; with it, each
	/// piece is narrowed for the slope it crosses, in steps of a tenth, down to a third, so a few
	/// paths stroke them all.
	private static func paths(_ lines: [[CLLocationCoordinate2D]], width: CGFloat, relief: Relief?, canvas: (CLLocationCoordinate2D) -> CGPoint) -> [(CGFloat, CGPath)] {
		guard let relief else {
			let path = CGMutablePath()
			for line in lines {
				path.addLines(between: line.map(canvas))
			}
			return [(width, path)]
		}
		var byStep: [Int: CGMutablePath] = [:]
		for line in lines where line.count >= 2 {
			let points = line.map(canvas)
			for index in 1..<line.count {
				let middle = CLLocationCoordinate2D(
					latitude: (line[index - 1].latitude + line[index].latitude) / 2,
					longitude: (line[index - 1].longitude + line[index].longitude) / 2
				)
				let step = min(max(Int((relief.widthFactor(at: middle) * 10).rounded()), 3), 10)
				let path = byStep[step] ?? CGMutablePath()
				path.move(to: points[index - 1])
				path.addLine(to: points[index])
				byStep[step] = path
			}
		}
		return byStep.sorted { $0.key < $1.key }.map { (width * CGFloat($0.key) / 10, $0.value) }
	}

	// MARK: Elevation labels

	/// Points, at a 2048-texel texture, for the label text, the clear space each side of it in
	/// its line, the distance along a line between its labels, and the least distance between any
	/// two labels.
	static let labelFontSize: CGFloat = 26
	static let labelGap: CGFloat = 6
	static let labelSpacing: CGFloat = 640
	static let labelClearance: CGFloat = 140
	/// The most labels on one texture, so the map stays a map rather than a page of numbers.
	static let maxLabels = 24

	/// The number printed on an index line: feet or meters, rounded, with no unit.
	static func labelText(elevationMeters: Double, metric: Bool) -> String {
		let value = metric ? elevationMeters : elevationMeters / 0.3048
		return Int(value.rounded()).formatted(.number.grouping(.never))
	}

	/// Where the elevations go: on the longest lines first, where the line runs nearly straight
	/// for the length of the number, `labelSpacing` apart along a line and `labelClearance` from
	/// any other label, inside `bounds` and the line's own tile. Sizes scale with `scale`.
	static func placeLabels(on lines: [CanvasLine], metric: Bool, scale: CGFloat, within bounds: CGRect, measure: (String) -> CGSize) -> [Label] {
		var placed: [Label] = []
		var taken: [CGRect] = []
		let spacing = labelSpacing * scale, clearance = labelClearance * scale
		let sorted = lines.filter { $0.points.count >= 2 }.map { ($0, arcLengths($0.points)) }.sorted { $0.1.last ?? 0 > $1.1.last ?? 0 }
		for (line, lengths) in sorted {
			guard placed.count < maxLabels, let total = lengths.last else { break }
			let text = labelText(elevationMeters: line.elevation, metric: metric)
			let size = measure(text)
			let half = size.width / 2 + labelGap * scale
			guard total >= 2 * half else { continue }
			var lastAlong = -CGFloat.infinity
			// Candidates every quarter spacing; a placed label pushes the next one a full spacing on.
			var along = max(half, min(total / 2, spacing / 2))
			while along <= total - half, placed.count < maxLabels {
				defer { along += spacing / 4 }
				guard along - lastAlong >= spacing else { continue }
				let start = point(at: along - half, on: line.points, lengths: lengths)
				let end = point(at: along + half, on: line.points, lengths: lengths)
				// Straight enough that the number lies along the line rather than across a bend: the
				// line stays within a third of the text's height of a straight run under it, and isn't
				// so jagged that it's much longer than that run. The terrain's small wiggles pass both.
				guard hypot(end.x - start.x, end.y - start.y) >= 0.8 * 2 * half,
					  straysFromChord(line.points, lengths: lengths, from: along - half, to: along + half) <= size.height / 3 else { continue }
				let center = point(at: along, on: line.points, lengths: lengths)
				guard line.clip.contains(center) else { continue }
				let label = Label(text: text, center: center, angle: readableAngle(from: start, to: end), size: size)
				let corners = label.corners()
				guard corners.allSatisfy(bounds.contains) else { continue }
				let box = boundingBox(corners).insetBy(dx: -clearance / 2, dy: -clearance / 2)
				guard !taken.contains(where: { $0.intersects(box) }) else { continue }
				placed.append(label)
				taken.append(box)
				lastAlong = along
			}
		}
		return placed
	}

	/// The direction from `start` to `end`, turned half a turn when needed so the number reads left
	/// to right rather than upside down.
	static func readableAngle(from start: CGPoint, to end: CGPoint) -> CGFloat {
		var angle = atan2(end.y - start.y, end.x - start.x)
		if angle > .pi / 2 { angle -= .pi }
		if angle < -.pi / 2 { angle += .pi }
		return angle
	}

	/// The farthest the line's points between `from` and `to` along it lie from the straight run
	/// between the line's points at those distances.
	private static func straysFromChord(_ points: [CGPoint], lengths: [CGFloat], from: CGFloat, to: CGFloat) -> CGFloat {
		let start = point(at: from, on: points, lengths: lengths)
		let end = point(at: to, on: points, lengths: lengths)
		let chord = hypot(end.x - start.x, end.y - start.y)
		guard chord > 0 else { return .infinity }
		var farthest: CGFloat = 0
		for (index, point) in points.enumerated() where lengths[index] > from && lengths[index] < to {
			let offset = abs((end.x - start.x) * (start.y - point.y) - (start.x - point.x) * (end.y - start.y)) / chord
			farthest = max(farthest, offset)
		}
		return farthest
	}

	private static func arcLengths(_ points: [CGPoint]) -> [CGFloat] {
		var lengths: [CGFloat] = [0]
		for index in 1..<points.count {
			lengths.append(lengths[index - 1] + hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y))
		}
		return lengths
	}

	private static func point(at distance: CGFloat, on points: [CGPoint], lengths: [CGFloat]) -> CGPoint {
		guard let after = lengths.firstIndex(where: { $0 >= distance }), after > 0 else { return points[0] }
		let span = lengths[after] - lengths[after - 1]
		let fraction = span > 0 ? (distance - lengths[after - 1]) / span : 0
		let a = points[after - 1], b = points[after]
		return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
	}

	private static func boundingBox(_ points: [CGPoint]) -> CGRect {
		let xs = points.map(\.x), ys = points.map(\.y)
		return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
	}

	private struct TextLine {
		let line: CTLine
		let size: CGSize
		let descent: CGFloat
	}

	/// The text set in `font`, filled with `color`, or with `halo` its outline only, for drawing
	/// under the fill.
	private static func textLine(_ text: String, font: UIFont, color: UIColor, halo: UIColor? = nil) -> TextLine {
		var attributes: [NSAttributedString.Key: Any] = [.font: font as CTFont, .foregroundColor: color.cgColor]
		if let halo {
			attributes[.strokeColor] = halo.cgColor
			attributes[.strokeWidth] = 18 as CGFloat
		}
		let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
		var ascent: CGFloat = 0, descent: CGFloat = 0
		let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
		return TextLine(line: line, size: CGSize(width: width, height: ascent + descent), descent: descent)
	}
}
