//
//  SpatialOverlayEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
#if os(visionOS)
import Metal
import RealityKit
import UIKit

/// An image draped over the terrain: a copy of the terrain's surface floating `lift` above it,
/// with the image as an unlit, see-through material, so it follows the hills and uses the
/// terrain's own texture coordinates. It has no collision or input target, so looks and taps go
/// through to the pins and the terrain. The coverage and weather radar drapes are made here.
enum SpatialOverlayEntity {
	/// The drapes are drawn in their layer's order rather than by distance, so two see-through
	/// sheets a hair apart never swap as the viewer moves.
	static let sortGroup = ModelSortGroup()

	@MainActor
	static func make(layer: SpatialOverlayLayer, geometry: SpatialTerrainGeometry, image: CGImage, opacity: Float) async throws -> ModelEntity {
		let surface = geometry.overlaySurface(lift: layer.lift)
		var descriptor = MeshDescriptor(name: layer.name)
		descriptor.positions = MeshBuffer(surface.positions)
		descriptor.normals = MeshBuffer(surface.normals)
		descriptor.textureCoordinates = MeshBuffer(surface.uvs)
		descriptor.primitives = .triangles(surface.indices)
		let mesh = try await MeshResource(from: [descriptor])

		let texture = try await texture(for: image)
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
		entity.name = layer.name
		entity.components.set(ModelSortGroupComponent(group: sortGroup, order: layer.sortOrder))
		return entity
	}

	/// The image as a drape texture.
	@MainActor
	static func texture(for image: CGImage) async throws -> TextureResource {
		var options = TextureResource.CreateOptions(semantic: .color)
		options.mipmapsMode = .allocateAndGenerateAll
		// No resource name: RealityKit reuses a named texture, so every rebuild would keep the first image.
		return try await TextureResource(image: image, options: options)
	}

	/// Puts a new image on a drape without rebuilding its mesh: a new radar period on the same terrain.
	@MainActor
	static func setTexture(_ texture: TextureResource, on entity: ModelEntity) {
		guard var materials = entity.model?.materials else { return }
		for index in materials.indices {
			guard var material = materials[index] as? UnlitMaterial else { continue }
			material.color.texture?.resource = texture
			materials[index] = material
		}
		entity.model?.materials = materials
	}

	/// Changes how see-through a drape is without rebuilding it.
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

/// One drape: its entity name, how far it floats above the terrain, and its place in the draw
/// order, lowest first.
struct SpatialOverlayLayer {
	let name: String
	let lift: Float
	let sortOrder: Int32
}
#endif
