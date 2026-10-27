//
//  SpatialWeatherRadar.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
import CoreGraphics
import CoreLocation
import Foundation
import ImageIO

/// A fetched radar image; CGImage is immutable, just not marked Sendable.
struct SpatialWeatherRadarImage: @unchecked Sendable {
	let image: CGImage
}

/// The last radar image fetched, kept so a terrain rebuilt for the same box (dark map, contours,
/// another layer) is draped again without a fetch, and a failed fetch keeps the rain that is up
/// for one more period.
struct SpatialWeatherRadarCache: @unchecked Sendable {
	let bounds: GeoBounds
	let refreshPeriod: Int
	let image: CGImage

	/// The image for this box in this period, if it is this one.
	func current(bounds: GeoBounds, refreshPeriod: Int) -> CGImage? {
		self.bounds == bounds && self.refreshPeriod == refreshPeriod ? image : nil
	}

	/// What to leave up after a failed fetch: the last image, as long as it is of the same box and
	/// at most one period old. Rain from another box would be drawn in the wrong place, and older
	/// rain has moved on, so the drape clears rather than show it.
	func fallback(bounds: GeoBounds, refreshPeriod: Int) -> CGImage? {
		self.bounds == bounds && self.refreshPeriod >= refreshPeriod - 1 ? image : nil
	}
}

/// What the drape does after a failed fetch.
enum SpatialWeatherRadarRecovery: Equatable {
	/// The last image is of this box and at most a period old: leave it up.
	case keep(CGImage)
	/// Nothing to leave up: try once more after `SpatialWeatherRadar.retryDelay`.
	case retry
	/// Nothing to leave up and the retry failed too: clear, and wait for the next period.
	case clear

	static func == (lhs: Self, rhs: Self) -> Bool {
		switch (lhs, rhs) {
		case (.keep(let left), .keep(let right)): return left === right
		case (.retry, .retry), (.clear, .clear): return true
		default: return false
		}
	}
}

/// The NOAA radar for the spatial map: one image of the terrain's box, laid out like its map
/// image, so the drape can use the terrain's own texture coordinates.
enum SpatialWeatherRadar {
	/// Longest edge of the drape. The radar's cells are 1 km, so this is finer than the data even
	/// on the widest table, and the cells are drawn smooth to fill it.
	static let textureEdge = 1024
	static let timeout: TimeInterval = 15
	/// How long after a failed fetch that left nothing up to try once more.
	static let retryDelay: TimeInterval = 30

	/// What to ask the server for: the box's radar cells, one pixel each, with one cell more on
	/// every side, or on a table wider than the drape's pixels, the box at the drape's size.
	/// Either way a Mercator image that lines up with the terrain the way the map snapshot does.
	struct Plan {
		let request: URLRequest
		/// The drape's size in pixels.
		let size: CGSize
		/// The cells to draw smooth at `size`; nil when the server's image is already the drape.
		let grid: WeatherRadarCellGrid?
	}

	static func plan(for frame: SpatialFrame, refreshPeriod: Int) -> Plan {
		let size = SpatialTextureRenderer.pixelSize(for: frame, maxEdge: textureEdge)
		let bounds = WeatherRadar.mercatorBounds(for: frame.bounds)
		let grid = WeatherRadarCellGrid(bounds: bounds, outputWidth: Int(size.width), outputHeight: Int(size.height))
		let url = if let grid {
			WeatherRadar.imageURL(mercatorBounds: grid.paddedBounds, width: grid.requestWidth, height: grid.requestHeight, refreshPeriod: refreshPeriod)
		} else {
			WeatherRadar.imageURL(mercatorBounds: bounds, width: Int(size.width), height: Int(size.height), refreshPeriod: refreshPeriod)
		}
		return Plan(request: URLRequest(url: url, timeoutInterval: timeout), size: size, grid: grid)
	}

	/// Whether there is a radar to fetch: it is turned on, offered where the device is, there is
	/// a network, and the box is inside the radar's coverage. The table can be far from the
	/// device, and a box outside the radar gets a blank image rather than an error.
	static func shouldFetch(show: Bool, offered: Bool, networkAvailable: Bool, center: CLLocationCoordinate2D) -> Bool {
		show && offered && networkAvailable && WeatherRadar.covers(center)
	}

	/// What a rebuild is keyed on: the terrain, the five-minute period and whether to fetch at all.
	static func key(revision: Int, refreshPeriod: Int, fetch: Bool) -> String {
		"\(revision)|\(refreshPeriod)|\(fetch)"
	}

	/// After a failed fetch: keep the last image if it is of this box and at most a period old.
	/// With nothing to keep, try once more soon rather than leave the table bare until the next
	/// period, unless `retried` says that was done already.
	static func afterFailedFetch(cache: SpatialWeatherRadarCache?, bounds: GeoBounds, refreshPeriod: Int, retried: Bool) -> SpatialWeatherRadarRecovery {
		if let image = cache?.fallback(bounds: bounds, refreshPeriod: refreshPeriod) { return .keep(image) }
		return retried ? .clear : .retry
	}

	/// Fetches and decodes the image. Anything but an image the server is happy with is an
	/// error, never a blank drape.
	static func fetch(_ plan: Plan, session: URLSession = .shared) async throws -> SpatialWeatherRadarImage {
		let (data, response) = try await session.data(for: plan.request)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw URLError(.badServerResponse)
		}
		let decoded = await Task.detached(priority: .userInitiated) { () -> SpatialWeatherRadarImage? in
			guard let image = decode(data) else { return nil }
			guard let grid = plan.grid else { return SpatialWeatherRadarImage(image: image) }
			return WeatherRadarSmoothing.smooth(image, grid: grid, width: Int(plan.size.width), height: Int(plan.size.height))
				.map(SpatialWeatherRadarImage.init)
		}.value
		guard let decoded else { throw URLError(.cannotDecodeContentData) }
		return decoded
	}

	/// Decodes the PNG into premultiplied RGBA, the coverage canvas format, at its own size. The
	/// server's PNG has straight alpha; handed to the texture as it is, the edges of the rain fringe.
	static func decode(_ data: Data) -> CGImage? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil),
			  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
		let width = image.width, height = image.height
		guard width > 0, height > 0,
			  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
									  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		return context.makeImage()
	}
}
