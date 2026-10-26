//
//  CinemaAnchors.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/24/26.
//
#if os(visionOS)
import CinemaContent
import Foundation
import OSLog
import simd

/// The boards in a cinema environment's image that the app draws live panels on.
enum CinemaBoard: String, CaseIterable {
	/// The whiteboard behind the viewer's left shoulder: the team roster.
	case teamStatus
	/// The print on the right wall by the door: the latest trace route's share card.
	case traceRoute
	/// The plain front wall: the screen that shows the app's sections. Only an anchor in the image.
	case screen
}

/// Where the boards in an environment's image sit. The render script writes this next to the
/// image (scripts/cinema/tent_base.py, `anchor()`), so a re-render can't move a board without
/// moving its panel. Meters, RealityKit axes, relative to the camera the image was rendered from,
/// with the image's center toward -Z.
struct CinemaAnchors: Decodable {
	/// The eye height the images are rendered from, for an environment whose anchors don't load.
	static let seatedEyeHeight: Float = 1.15

	/// The camera's height above the floor in the render.
	let eyeHeight: Float
	let boards: [String: Board]

	struct Board: Decodable {
		let position: SIMD3<Float>
		let width: Float
		let height: Float
		/// Turns a panel, whose +X is its right and +Z its front, to lie on the board.
		let orientation: simd_quatf

		/// How much to push the board out from the camera, and grow it, so its farthest corner sits
		/// at `distance`. Pushed out along the lines from the camera it still covers the same part
		/// of the image, and far out it has about the painting's stereo depth.
		func distanceScale(within distance: Float) -> Float {
			let right = orientation.act([width / 2, 0, 0])
			let up = orientation.act([0, height / 2, 0])
			let farthest = [right + up, right - up, -right + up, -right - up]
				.map { simd_length(position + $0) }
				.max() ?? 0
			return farthest > 0 ? distance / farthest : 1
		}

		private enum CodingKeys: String, CodingKey {
			case center, size, right, normal
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			let center = try Self.vector(container, .center)
			let size = try container.decode([Float].self, forKey: .size)
			guard size.count == 2 else {
				throw DecodingError.dataCorruptedError(forKey: .size, in: container, debugDescription: "Expected a width and a height")
			}
			let right = simd_normalize(try Self.vector(container, .right))
			let normal = simd_normalize(try Self.vector(container, .normal))
			position = center
			width = size[0]
			height = size[1]
			orientation = simd_quatf(simd_float3x3(columns: (right, simd_cross(normal, right), normal)))
		}

		private static func vector(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> SIMD3<Float> {
			let values = try container.decode([Float].self, forKey: key)
			guard values.count == 3 else {
				throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected x, y and z")
			}
			return SIMD3(values[0], values[1], values[2])
		}
	}

	func board(_ board: CinemaBoard) -> Board? {
		boards[board.rawValue]
	}

	/// The anchors for `environment`, or nil if it has none or they don't load.
	static func load(for environment: CinemaEnvironment) -> CinemaAnchors? {
		guard let url = cinemaEnvironmentAnchorsURL(named: environment.imageName) else { return nil }
		do {
			return try JSONDecoder().decode(CinemaAnchors.self, from: Data(contentsOf: url))
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't read the anchors for \(environment.imageName, privacy: .public): \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}
}
#endif
