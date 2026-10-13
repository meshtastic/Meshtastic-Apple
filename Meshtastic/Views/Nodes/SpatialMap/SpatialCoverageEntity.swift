//
//  SpatialCoverageEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
#if os(visionOS)
import Metal
import RealityKit
import UIKit

/// The coverage overlay: a copy of the terrain's surface floating just above it, with the coverage
/// image as an unlit, see-through material. It has no collision or input target, so looks and
/// taps go through to the pins and the terrain.
enum SpatialCoverageEntity {
	static let name = "coverage"

	@MainActor
	static func make(geometry: SpatialTerrainGeometry, image: CGImage, opacity: Float) async throws -> ModelEntity {
		let surface = geometry.overlaySurface()
		var descriptor = MeshDescriptor(name: name)
		descriptor.positions = MeshBuffer(surface.positions)
		descriptor.normals = MeshBuffer(surface.normals)
		descriptor.textureCoordinates = MeshBuffer(surface.uvs)
		descriptor.primitives = .triangles(surface.indices)
		let mesh = try await MeshResource(from: [descriptor])

		var textureOptions = TextureResource.CreateOptions(semantic: .color)
		textureOptions.mipmapsMode = .allocateAndGenerateAll
		// No resource name: RealityKit reuses a named texture, so every rebuild would keep the first image.
		let texture = try await TextureResource(image: image, options: textureOptions)
		let sampler = MTLSamplerDescriptor()
		sampler.sAddressMode = .clampToEdge
		sampler.tAddressMode = .clampToEdge
		sampler.minFilter = .linear
		sampler.magFilter = .linear
		sampler.mipFilter = .linear
		sampler.maxAnisotropy = 8

		var material = UnlitMaterial()
		material.color = .init(tint: .white, texture: .init(texture, sampler: .init(sampler)))
		material.blending = .transparent(opacity: .init(floatLiteral: opacity))
		let entity = ModelEntity(mesh: mesh, materials: [material])
		entity.name = name
		return entity
	}

	/// Changes how see-through the overlay is without rebuilding it.
	@MainActor
	static func setOpacity(_ opacity: Float, on entity: ModelEntity) {
		guard var materials = entity.model?.materials else { return }
		for index in materials.indices {
			guard var material = materials[index] as? UnlitMaterial else { continue }
			material.blending = .transparent(opacity: .init(floatLiteral: opacity))
			materials[index] = material
		}
		entity.model?.materials = materials
	}
}
#endif
