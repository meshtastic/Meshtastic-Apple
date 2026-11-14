//
//  SpatialBuildingsEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//
#if os(visionOS)
import RealityKit
import UIKit

/// The Buildings option's entity: every building on the disk in one mesh, plain and matte like a
/// planning model. No collision shape, so a look and pinch passes through to the pins and terrain.
enum SpatialBuildingsEntity {
	@MainActor
	static func make(_ mesh: SpatialMeshData, dark: Bool) async throws -> ModelEntity? {
		guard mesh.triangleCount > 0 else { return nil }
		var descriptor = MeshDescriptor(name: "buildings")
		descriptor.positions = MeshBuffer(mesh.positions)
		descriptor.normals = MeshBuffer(mesh.normals)
		descriptor.primitives = .triangles(mesh.indices)
		let resource = try await MeshResource(from: [descriptor])
		let entity = ModelEntity(mesh: resource, materials: [material(dark: dark)])
		entity.name = "buildings"
		return entity
	}

	/// Shades the buildings for the dark map or the light one, without building them again.
	@MainActor
	static func setDark(_ dark: Bool, on entity: ModelEntity) {
		entity.model?.materials = [material(dark: dark)]
	}

	private static func material(dark: Bool) -> PhysicallyBasedMaterial {
		var material = PhysicallyBasedMaterial()
		material.baseColor = .init(tint: UIColor(white: dark ? 0.55 : 0.9, alpha: 1))
		material.roughness = 0.9
		material.metallic = 0.0
		return material
	}
}
#endif
