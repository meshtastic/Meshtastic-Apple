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
/// with a clamped sampler so the border texels never wrap, and a collision shape for taps that
/// follows the surface.
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
		// Collide with the mesh itself, so the pins standing on it are never inside the terrain's
		// hit shape and a look-and-pinch reaches them first.
		entity.components.set(CollisionComponent.inputTarget([try await ShapeResource.generateStaticMesh(from: mesh)]))
		entity.components.set(InputTargetComponent())
		return entity
	}
}
#endif
