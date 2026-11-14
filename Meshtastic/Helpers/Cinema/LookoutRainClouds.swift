//
//  LookoutRainClouds.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//
#if os(visionOS)
import CoreGraphics
import CoreLocation
import Foundation
import Metal
import RealityKit
import UIKit

/// The weather radar out the windows of a room with real terrain: the rain as a level sheet of
/// cloud over the ground round the site, placed by bearing and distance the way the terrain is, so
/// it sits over the right ridges and the room's glass hides it except through the windows. Far rain
/// fades into the haze like far ridges.
enum LookoutRainClouds {
	/// Rings of the sheet from just past the roof out to the terrain's edge, and samples round each.
	static let rings = 40
	static let spokes = 360
	/// The sheet starts this close, so it has no edge overhead in a room with no roof.
	static let innerRadius = 100.0
	static let maxRadius = LookoutTerrain.maxRadius
	/// Where the cloud's base is, in meters above sea level, and at least how far over the site's
	/// ground it stays, so it floats over a high summit rather than through it.
	static let cloudBase = 1_500.0
	static let siteClearance = 300.0
	/// How far over the sharp sheet the soft one floats, in meters.
	static let softRise = 150.0
	/// The sheets' strength where the rain is solid: the sharp one and the soft one over it.
	static let opacities: [Float] = [0.4, 0.35]
	/// How much of the soft sheet's longest edge it is blurred by.
	static let softBlur = 0.008

	/// The cloud's base over `site`, in meters above sea level.
	static func altitude(for site: LookoutSite) -> Double {
		max(cloudBase, Double(site.elevation) + siteClearance)
	}

	/// The box the radar is fetched for: the site, out to the terrain's edge on every side.
	static func bounds(around site: LookoutSite) -> GeoBounds {
		let latitudeSpan = maxRadius / SpatialFrame.metersPerDegreeLatitude
		let longitudeSpan = maxRadius / (SpatialFrame.metersPerDegreeLatitude * cos(site.latitude * .pi / 180))
		return GeoBounds(minLon: site.longitude - longitudeSpan, minLat: site.latitude - latitudeSpan,
		                 maxLon: site.longitude + longitudeSpan, maxLat: site.latitude + latitudeSpan)
	}

	/// The point a true `bearing` and `distance` from the site, on a flat earth: fine at this size
	/// for lining the rain up with ground drawn a few pixels a kilometer.
	static func coordinate(from site: LookoutSite, bearing: Double, distance: Double) -> CLLocationCoordinate2D {
		let radians = bearing * .pi / 180
		let north = cos(radians) * distance, east = sin(radians) * distance
		return CLLocationCoordinate2D(
			latitude: site.latitude + north / SpatialFrame.metersPerDegreeLatitude,
			longitude: site.longitude + east / (SpatialFrame.metersPerDegreeLatitude * cos(site.latitude * .pi / 180))
		)
	}

	/// How much of the rain shows `distance` meters out: all of it close in, fading with the
	/// terrain's haze, and none past the terrain's edge. Far rain at cloud height sits only a degree
	/// or so over the horizon, where it would draw as thin stripes, so it's mostly gone by then.
	static func visibility(distance: Double) -> Double {
		guard distance <= maxRadius else { return 0 }
		return exp(-distance / LookoutForest.hazeDistance)
	}

	/// The sheet's buffers.
	struct Mesh: Sendable {
		let positions: [SIMD3<Float>]
		let uvs: [SIMD2<Float>]
		let indices: [UInt32]
	}

	/// The sheet `rise` meters over the cloud base, seen from the room on `site` turned to
	/// `heading`, with texture coordinates into a Mercator radar image of `frame`'s box.
	static func mesh(site: LookoutSite, heading: Double, frame: SpatialFrame, rise: Double = 0) -> Mesh {
		let eye = LookoutTerrain.eyeElevation(for: site)
		let height = altitude(for: site) + rise - eye
		var positions: [SIMD3<Float>] = []
		var uvs: [SIMD2<Float>] = []
		positions.reserveCapacity(rings * spokes)
		uvs.reserveCapacity(rings * spokes)
		for ring in 0..<rings {
			let distance = innerRadius * pow(maxRadius / innerRadius, Double(ring) / Double(rings - 1))
			let depth = LookoutTerrain.depth(distance)
			for spoke in 0..<spokes {
				let bearing = 360 * Double(spoke) / Double(spokes)
				positions.append(LookoutTerrain.direction(bearing: bearing, distance: distance, rise: height, heading: heading) * depth)
				let point = coordinate(from: site, bearing: bearing, distance: distance)
				let fraction = frame.mercatorFraction(latitude: point.latitude, longitude: point.longitude)
				uvs.append(SIMD2(Float(fraction.x), Float(SpatialTerrainGeometry.flipTextureV ? 1 - fraction.y : fraction.y)))
			}
		}
		var indices: [UInt32] = []
		indices.reserveCapacity((rings - 1) * spokes * 6)
		for ring in 0..<(rings - 1) {
			for spoke in 0..<spokes {
				let next = (spoke + 1) % spokes
				let a = UInt32(ring * spokes + spoke), b = UInt32(ring * spokes + next)
				let c = UInt32((ring + 1) * spokes + spoke), d = UInt32((ring + 1) * spokes + next)
				indices += [a, c, b, b, c, d]
			}
		}
		return Mesh(positions: positions, uvs: uvs, indices: indices)
	}

	/// The radar with far rain faded, then the sharp and soft sheets' images.
	static func images(for radar: CGImage, site: LookoutSite, frame: SpatialFrame) -> [CGImage]? {
		let center = CLLocation(latitude: site.latitude, longitude: site.longitude)
		let faded = SpatialRainClouds.faded(radar) { u, v in
			let point = CLLocation(latitude: frame.latitude(atMercatorFraction: v), longitude: frame.longitude(atFraction: u))
			return visibility(distance: point.distance(from: center))
		}
		guard let faded, let soft = SpatialRainClouds.softened(faded, blur: softBlur) else { return nil }
		return [faded, soft]
	}

	/// The sheets' images, and their meshes when they're to be built rather than reused.
	struct Sheets: @unchecked Sendable {
		let meshes: [Mesh]
		let images: [CGImage]
	}

	/// Everything for the sheets from one radar image, built off the main actor.
	static func sheets(for radar: CGImage, site: LookoutSite, heading: Double, frame: SpatialFrame, withMeshes: Bool) -> Sheets? {
		guard let images = images(for: radar, site: site, frame: frame) else { return nil }
		let meshes = withMeshes ? [mesh(site: site, heading: heading, frame: frame), mesh(site: site, heading: heading, frame: frame, rise: softRise)] : []
		return Sheets(meshes: meshes, images: images)
	}

	// MARK: Entity

	static let entityName = "rainClouds"
	private static let sortGroup = ModelSortGroup()

	/// The sheets as one entity, sharp under soft.
	@MainActor
	static func entity(meshes: [Mesh], images: [CGImage]) async throws -> Entity {
		let root = Entity()
		root.name = entityName
		for (index, mesh) in meshes.enumerated() where index < images.count && index < opacities.count {
			var descriptor = MeshDescriptor(name: "\(entityName)\(index)")
			descriptor.positions = MeshBuffer(mesh.positions)
			descriptor.textureCoordinates = MeshBuffer(mesh.uvs)
			descriptor.primitives = .triangles(mesh.indices)
			let resource = try await MeshResource(from: [descriptor])
			let sheet = ModelEntity(mesh: resource, materials: [material(texture: try await SpatialOverlayEntity.texture(for: images[index]), opacity: opacities[index])])
			sheet.name = "\(entityName)\(index)"
			sheet.components.set(ModelSortGroupComponent(group: sortGroup, order: Int32(index)))
			root.addChild(sheet)
		}
		return root
	}

	/// Puts a new period's rain on the sheets without rebuilding them.
	@MainActor
	static func setImages(_ images: [CGImage], on root: Entity) async throws {
		for (index, image) in images.enumerated() {
			guard let sheet = root.findEntity(named: "\(entityName)\(index)") as? ModelEntity else { continue }
			SpatialOverlayEntity.setTexture(try await SpatialOverlayEntity.texture(for: image), on: sheet)
		}
	}

	@MainActor
	private static func material(texture: TextureResource, opacity: Float) -> UnlitMaterial {
		let sampler = MTLSamplerDescriptor()
		sampler.sAddressMode = .clampToZero
		sampler.tAddressMode = .clampToZero
		sampler.minFilter = .linear
		sampler.magFilter = .linear
		sampler.mipFilter = .linear
		var material = UnlitMaterial()
		material.color = .init(tint: .white, texture: .init(texture, sampler: .init(sampler)))
		material.blending = .transparent(opacity: .init(floatLiteral: opacity))
		// Seen from under it, whichever way its triangles wind.
		material.faceCulling = .none
		// Where there's no rain the sheet is clear, so it mustn't hide the sky drawn after it.
		material.writesDepth = false
		return material
	}
}
#endif
