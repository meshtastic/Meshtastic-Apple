//
//  RooftopCity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
#if os(visionOS)
import CoreGraphics
import CoreLocation
import Foundation
import Metal
import OSLog
import RealityKit
import simd
import UIKit

/// The real city round the cinema's rooftop, as meshes built off the main actor: one for the
/// walls in each of `RooftopCity.shades` levels of the sunset's light, and one for the roofs.
struct RooftopCityModel: Sendable {
	struct Part: Sendable {
		var positions: [SIMD3<Float>] = []
		var textureCoordinates: [SIMD2<Float>] = []
		var indices: [UInt32] = []
	}

	/// The walls, darkest first.
	let walls: [Part]
	let roofs: Part
	let buildings: Int
}

/// The buildings near a rooftop from the downloaded basemaps, drawn round it in the cinema the
/// way the lookout's terrain is: every corner along its own line of sight from the deck, at the
/// terrain's depth for its distance, so the city stands on the terrain where it should.
enum RooftopCity {
	/// Buildings this far from the rooftop are drawn; past it the terrain carries on alone. From a
	/// tall roof they're down near the horizon by then.
	static let radius = 3_500.0
	/// Tiles decoded for the buildings round the rooftop: enough for the radius at zoom 15 in most
	/// of the world.
	static let maxTiles = 110
	static let triangleBudget = 240_000
	/// How many levels of light the walls are drawn in, from facing away from the sun to facing it.
	static let shades = 6
	/// The window texture repeats every this many meters along a wall and up it: eight bays of
	/// 1.6 m, and eight floors of 3.6 m.
	static let tileWidth: Float = 12.8
	static let tileHeight: Float = 28.8
	/// Walls longer than this are cut into pieces, so a long wall follows its line of sight from
	/// the deck instead of cutting straight across the terrain's depths.
	static let segment = 40.0
	/// Each piece of wall spans at most this many degrees across and up as seen from the deck. A
	/// flat piece spanning more would cut inside the room's sphere, in front of the deck.
	static let maxSpan = 5.0
	/// The deck hides everything more than this far below level (its edge is about 17° down), so a
	/// building whose roof is lower than that from its nearest corner isn't drawn.
	static let deckDip = 15.0

	/// The box of buildings to decode round `site`.
	static func bounds(around site: LookoutSite) -> GeoBounds {
		let metersPerDegreeLatitude = SpatialFrame.metersPerDegreeLatitude
		let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(site.latitude * .pi / 180)
		let dLat = radius / metersPerDegreeLatitude, dLon = radius / metersPerDegreeLongitude
		return GeoBounds(minLon: site.longitude - dLon, minLat: site.latitude - dLat, maxLon: site.longitude + dLon, maxLat: site.latitude + dLat)
	}

	/// The meshes for `footprints`, each standing on `grounds` (its ground's elevation, nil where
	/// the terrain doesn't reach, which leaves the building out). The building the rooftop is on is
	/// left out: the deck is drawn in the image. `heading` and `sun` are as for the terrain. Nil
	/// when no building is drawn, or the task is cancelled.
	static func build(site: LookoutSite, footprints: [SpatialBuildingFootprint], grounds: [Double?], heading: Double, sun: (azimuth: Float, elevation: Float)) -> RooftopCityModel? {
		let metersPerDegreeLatitude = SpatialFrame.metersPerDegreeLatitude
		let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(site.latitude * .pi / 180)
		let eye = LookoutTerrain.eyeElevation(for: site)
		let sunBearing = (Double(sun.azimuth) + heading) * .pi / 180
		let sunElevation = Double(sun.elevation) * .pi / 180
		// East, north: the sun's direction over the ground.
		let light = SIMD2(sin(sunBearing), cos(sunBearing)) * cos(sunElevation)

		struct Placed {
			let outline: [SIMD2<Double>]
			let bottom: Double
			let top: Double
			let distance: Double
			let offset: Float
		}
		// A sky deck hangs off its tower's face, so the tower is found a little behind the seat.
		let home = site.facing.map { RooftopSites.tower(behind: site.coordinate, facing: $0) } ?? site.coordinate
		var placed: [Placed] = []
		for (index, footprint) in footprints.enumerated() {
			guard index < grounds.count, let ground = grounds[index] else { continue }
			if SpatialBuildings.contains(footprint.outline, home) { continue }
			var outline = footprint.outline.map { c in
				SIMD2((c.longitude - site.longitude) * metersPerDegreeLongitude, (c.latitude - site.latitude) * metersPerDegreeLatitude)
			}
			outline = cleaned(outline)
			guard outline.count >= 3 else { continue }
			let area = signedArea(outline)
			guard abs(area) > 1 else { continue }
			if area < 0 { outline.reverse() }
			let nearest = outline.map { simd_length($0) }.min() ?? .infinity
			guard nearest <= radius else { continue }
			let height = max(footprint.height ?? SpatialBuildings.defaultHeight, 1)
			let minHeight = min(max(footprint.minHeight, 0), height - 1)
			// A sky deck's glass floor hides nothing below it.
			guard site.isSkyDeck || ground + height - eye > -nearest * tan(deckDip * .pi / 180) else { continue }
			// Each building's windows start somewhere different in the texture, so neighbors don't match.
			let offset = Float(abs(Int(outline[0].x * 7 + outline[0].y * 13)) % 97) / 97
			placed.append(Placed(outline: outline, bottom: ground + minHeight, top: ground + height, distance: nearest, offset: offset))
		}
		guard !placed.isEmpty else { return nil }
		placed.sort { $0.distance < $1.distance }

		func position(_ point: SIMD2<Double>, _ elevation: Double) -> SIMD3<Float> {
			let distance = max(1, simd_length(point))
			let bearing = atan2(point.x, point.y) * 180 / .pi
			return LookoutTerrain.direction(bearing: bearing, distance: distance, rise: elevation - eye, heading: heading) * LookoutTerrain.depth(distance)
		}

		var walls = [RooftopCityModel.Part](repeating: .init(), count: shades)
		var roofs = RooftopCityModel.Part()
		var triangles = 0
		var buildings = 0
		for building in placed {
			if Task.isCancelled { return nil }
			let outline = building.outline
			let roof = SpatialBuildings.triangulate(outline.map { SIMD2(Float($0.x), Float($0.y)) })
			var cost = roof.count / 3
			for i in outline.indices {
				let grid = pieces(outline[i], outline[(i + 1) % outline.count], bottom: building.bottom, top: building.top, eye: eye)
				cost += 2 * grid.across * grid.up
			}
			guard triangles + cost <= triangleBudget else { break }
			triangles += cost
			buildings += 1

			let first = UInt32(roofs.positions.count)
			for point in outline {
				roofs.positions.append(position(point, building.top))
				roofs.textureCoordinates.append(SIMD2(Float(point.x) / 40, Float(point.y) / 40))
			}
			roofs.indices += roof.map { first + $0 }

			var along: Float = building.offset * tileWidth
			for i in outline.indices {
				let p = outline[i], q = outline[(i + 1) % outline.count]
				let edge = q - p
				let length = simd_length(edge)
				guard length > 0.01 else { continue }
				// Corners run counterclockwise, so the outward normal is the edge turned clockwise.
				let normal = SIMD2(edge.y, -edge.x) / length
				let lit = max(0, simd_dot(normal, light))
				let level = min(shades - 1, Int((0.15 + 0.85 * lit) * Double(shades - 1) + 0.5))
				let grid = pieces(p, q, bottom: building.bottom, top: building.top, eye: eye)
				let wallHeight = building.top - building.bottom
				for piece in 0..<grid.across {
					let a = p + edge * (Double(piece) / Double(grid.across))
					let b = p + edge * (Double(piece + 1) / Double(grid.across))
					let u0 = along / tileWidth
					along += Float(length) / Float(grid.across)
					let u1 = along / tileWidth
					for row in 0..<grid.up {
						let low = building.bottom + wallHeight * Double(row) / Double(grid.up)
						let high = building.bottom + wallHeight * Double(row + 1) / Double(grid.up)
						let v0 = Float(low - building.top) / tileHeight, v1 = Float(high - building.top) / tileHeight
						let start = UInt32(walls[level].positions.count)
						walls[level].positions += [position(a, low), position(b, low), position(b, high), position(a, high)]
						walls[level].textureCoordinates += [SIMD2(u0, v0), SIMD2(u1, v0), SIMD2(u1, v1), SIMD2(u0, v1)]
						walls[level].indices += [start, start + 1, start + 2, start, start + 2, start + 3]
					}
				}
			}
		}
		guard buildings > 0 else { return nil }
		return RooftopCityModel(walls: walls, roofs: roofs, buildings: buildings)
	}

	/// The city as one entity, unlit like the terrain: the walls in their window texture, darker the
	/// further they face from the sunset, and plain dark roofs.
	@MainActor
	static func entity(for model: RooftopCityModel) async throws -> ModelEntity {
		var descriptors: [MeshDescriptor] = []
		var materials: [any RealityKit.Material] = []
		let texture = try windowTexture().map { try TextureResource(image: $0, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)) }
		let sampler = MTLSamplerDescriptor()
		sampler.sAddressMode = .repeat
		sampler.tAddressMode = .repeat
		sampler.minFilter = .linear
		sampler.magFilter = .linear
		sampler.mipFilter = .linear
		for (level, part) in model.walls.enumerated() where !part.indices.isEmpty {
			var descriptor = MeshDescriptor(name: "rooftopWalls\(level)")
			descriptor.positions = MeshBuffer(part.positions)
			descriptor.textureCoordinates = MeshBuffer(part.textureCoordinates)
			descriptor.primitives = .triangles(part.indices)
			descriptor.materials = .allFaces(UInt32(materials.count))
			descriptors.append(descriptor)
			// From the cool shade of a wall facing away to the warm light on one facing the sun.
			let t = Float(level) / Float(shades - 1)
			let tint = UIColor(red: CGFloat(0.42 + 0.58 * t), green: CGFloat(0.44 + 0.4 * t), blue: CGFloat(0.52 + 0.18 * t), alpha: 1)
			var material = UnlitMaterial(color: tint)
			if let texture {
				material.color = .init(tint: tint, texture: .init(texture, sampler: .init(sampler)))
			}
			material.faceCulling = .none
			materials.append(material)
		}
		if !model.roofs.indices.isEmpty {
			var descriptor = MeshDescriptor(name: "rooftopRoofs")
			descriptor.positions = MeshBuffer(model.roofs.positions)
			descriptor.textureCoordinates = MeshBuffer(model.roofs.textureCoordinates)
			descriptor.primitives = .triangles(model.roofs.indices)
			descriptor.materials = .allFaces(UInt32(materials.count))
			descriptors.append(descriptor)
			var material = UnlitMaterial(color: UIColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1))
			material.faceCulling = .none
			materials.append(material)
		}
		let entity = ModelEntity(mesh: try MeshResource.generate(from: descriptors), materials: materials)
		entity.name = "RooftopCity"
		return entity
	}

	/// Eight bays by eight floors of windows: concrete between them, dark glass, and about one in
	/// six lit warm for the evening, each a little brighter or dimmer than the next.
	static func windowTexture() -> CGImage? {
		let size = 512
		let bay = size / 8, floor = size / 8
		var pixels = [UInt8](repeating: 255, count: size * size * 4)
		var state: UInt64 = 0x9E37_79B9_7F4A_7C15
		func random() -> Double {
			state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
			return Double(state >> 11) / Double(1 << 53)
		}
		let concrete = SIMD3<Double>(0.62, 0.6, 0.57)
		for row in 0..<8 {
			for column in 0..<8 {
				let lit = random() < 0.17
				let glow = 0.75 + 0.25 * random()
				let glass = lit ? SIMD3(1.0, 0.78, 0.48) * glow : SIMD3(0.16 + 0.06 * random(), 0.2, 0.26)
				for y in 0..<floor {
					for x in 0..<bay {
						// A window 70% of its bay wide and 62% of its floor tall, a band of concrete round it.
						let inWindow = x >= bay * 15 / 100 && x < bay * 85 / 100 && y >= floor * 22 / 100 && y < floor * 84 / 100
						let color = inWindow ? glass : concrete
						let index = ((row * floor + y) * size + column * bay + x) * 4
						pixels[index] = UInt8(min(255, color.x * 255))
						pixels[index + 1] = UInt8(min(255, color.y * 255))
						pixels[index + 2] = UInt8(min(255, color.z * 255))
					}
				}
			}
		}
		guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
		return CGImage(
			width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
			space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
			provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
		)
	}

	/// How many pieces a wall from `p` to `q` (meters east and north of the deck) is cut into, along
	/// it and up it, so none is longer than `segment` or spans more than `maxSpan` from the deck.
	private static func pieces(_ p: SIMD2<Double>, _ q: SIMD2<Double>, bottom: Double, top: Double, eye: Double) -> (across: Int, up: Int) {
		let nearest = max(1, min(simd_length(p), simd_length(q), simd_length((p + q) / 2)))
		let across = simd_distance(p, q)
		let turn = acos(max(-1, min(1, simd_dot(simd_normalize(p), simd_normalize(q))))) * 180 / .pi
		let rise = (atan((top - eye) / nearest) - atan((bottom - eye) / nearest)) * 180 / .pi
		let alongCount = max(Int((across / segment).rounded(.up)), Int((turn / maxSpan).rounded(.up)), 1)
		let upCount = max(Int((rise / maxSpan).rounded(.up)), 1)
		return (min(alongCount, 64), min(upCount, 32))
	}

	/// Drops repeated corners, including a last corner that closes the ring onto the first.
	private static func cleaned(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
		var result: [SIMD2<Double>] = []
		for p in points where result.last.map({ simd_distance($0, p) > 0.01 }) ?? true {
			result.append(p)
		}
		while result.count > 1, let first = result.first, let last = result.last, simd_distance(first, last) <= 0.01 {
			result.removeLast()
		}
		return result
	}

	/// Twice the area, positive when the corners run counterclockwise (east toward north).
	private static func signedArea(_ outline: [SIMD2<Double>]) -> Double {
		var sum = 0.0
		for i in outline.indices {
			let p = outline[i], q = outline[(i + 1) % outline.count]
			sum += p.x * q.y - q.x * p.y
		}
		return sum
	}
}
#endif
