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
/// another layer) is draped again without a fetch, and a failed fetch keeps the rain that is up.
struct SpatialWeatherRadarCache: @unchecked Sendable {
	let bounds: GeoBounds
	let refreshPeriod: Int
	let image: CGImage

	/// The image for this box in this period, if it is this one.
	func current(bounds: GeoBounds, refreshPeriod: Int) -> CGImage? {
		self.bounds == bounds && self.refreshPeriod == refreshPeriod ? image : nil
	}

	/// What to leave up after a failed fetch: the last image, as long as it is of the same box.
	/// Rain from another box would be drawn in the wrong place.
	func fallback(bounds: GeoBounds) -> CGImage? {
		self.bounds == bounds ? image : nil
	}
}

/// The NOAA radar for the spatial map: one image of the terrain's box, laid out like its map
/// image, so the drape can use the terrain's own texture coordinates.
enum SpatialWeatherRadar {
	/// Longest edge of the radar image. The radar's cells are 1 km, so this is finer than the data
	/// even on the widest table.
	static let textureEdge = 1024
	static let timeout: TimeInterval = 15

	/// The box's radar at the drape's size: a Mercator image of exactly the box, which lines up
	/// with the terrain the way the map snapshot does.
	static func request(for frame: SpatialFrame, refreshPeriod: Int) -> URLRequest {
		let size = SpatialTextureRenderer.pixelSize(for: frame, maxEdge: textureEdge)
		let url = WeatherRadar.imageURL(
			mercatorBounds: WeatherRadar.mercatorBounds(for: frame.bounds),
			width: Int(size.width), height: Int(size.height), refreshPeriod: refreshPeriod
		)
		return URLRequest(url: url, timeoutInterval: timeout)
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

	/// Fetches and decodes the image. Anything but an image the server is happy with is an
	/// error, never a blank drape.
	static func fetch(_ request: URLRequest, session: URLSession = .shared) async throws -> SpatialWeatherRadarImage {
		let (data, response) = try await session.data(for: request)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw URLError(.badServerResponse)
		}
		let decoded = await Task.detached(priority: .userInitiated) { decode(data).map(SpatialWeatherRadarImage.init) }.value
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
