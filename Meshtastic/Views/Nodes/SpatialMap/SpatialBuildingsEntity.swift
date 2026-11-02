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
		var material = PhysicallyBasedMaterial()
		material.baseColor = .init(tint: UIColor(white: dark ? 0.55 : 0.9, alpha: 1))
		material.roughness = 0.9
		material.metallic = 0.0
		let entity = ModelEntity(mesh: resource, materials: [material])
		entity.name = "buildings"
		return entity
	}
}
#endif
