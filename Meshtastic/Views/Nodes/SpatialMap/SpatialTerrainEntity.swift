//
//  SpatialTerrainEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import Metal
import RealityKit
import UIKit

/// Turns a built terrain into a RealityKit entity: the mesh, the map image as a lit material
/// with a clamped sampler so the border texels never wrap, and a round collision shape for taps.
enum SpatialTerrainEntity {
	@MainActor
	static func make(_ model: SpatialTerrainModel) async throws -> ModelEntity {
		let geometry = model.geometry
		var descriptor = MeshDescriptor(name: "terrain")
		descriptor.positions = MeshBuffer(geometry.positions)
		descriptor.normals = MeshBuffer(geometry.normals)
		descriptor.textureCoordinates = MeshBuffer(geometry.textureCoordinates)
		descriptor.primitives = .triangles(geometry.indices)
		let mesh = try await MeshResource(from: [descriptor])

		var textureOptions = TextureResource.CreateOptions(semantic: .color)
		textureOptions.mipmapsMode = .allocateAndGenerateAll
		// No resource name: RealityKit reuses a named texture, so every rebuild would keep the first image.
		let texture = try await TextureResource(image: model.texture, options: textureOptions)
		let sampler = MTLSamplerDescriptor()
		sampler.sAddressMode = .clampToEdge
		sampler.tAddressMode = .clampToEdge
		sampler.minFilter = .linear
		sampler.magFilter = .linear
		sampler.mipFilter = .linear
		sampler.maxAnisotropy = 8

		var material = PhysicallyBasedMaterial()
		material.baseColor = .init(tint: .white, texture: .init(texture, sampler: .init(sampler)))
		material.roughness = 1.0
		material.metallic = 0.0

		let entity = ModelEntity(mesh: mesh, materials: [material])
		entity.name = "terrain"
		// A round prism over the disk, so taps outside the map's edge miss it.
		let radius = geometry.transform.diskRadius
		let height: Float = 0.3
		let outline = (0..<64).map { k -> SIMD2<Float> in
			let angle = 2 * Float.pi * Float(k) / 64
			return SIMD2(radius * cos(angle), radius * sin(angle))
		}
		let points = outline.map { SIMD3($0.x, -0.02, $0.y) } + outline.map { SIMD3($0.x, height - 0.02, $0.y) }
		entity.components.set(CollisionComponent(shapes: [try await ShapeResource.generateConvex(from: points)]))
		entity.components.set(InputTargetComponent())
		return entity
	}
}
#endif
