//
//  SpatialTowerEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import RealityKit
import UIKit

extension SpatialMeshData {
	func meshResource() throws -> MeshResource {
		var descriptor = MeshDescriptor()
		descriptor.positions = MeshBuffers.Positions(positions)
		descriptor.normals = MeshBuffers.Normals(normals)
		descriptor.primitives = .triangles(indices)
		return try MeshResource.generate(from: [descriptor])
	}
}

/// The meshes and materials towers share: one lattice mesh per height, built the first time a
/// tower that tall is shown, and the light and signal ring every tower uses.
@MainActor
enum SpatialTowerParts {
	private static var meshes: [Float: MeshResource] = [:]

	static func mesh(height: Float) -> MeshResource? {
		if let cached = meshes[height] { return cached }
		guard let mesh = try? SpatialTower.geometry(height: height).meshResource() else { return nil }
		meshes[height] = mesh
		return mesh
	}

	static let material: PhysicallyBasedMaterial = {
		var material = PhysicallyBasedMaterial()
		material.baseColor = .init(tint: UIColor(white: 0.86, alpha: 1))
		material.metallic = 0.55
		material.roughness = 0.35
		return material
	}()

	static let beaconMesh = MeshResource.generateSphere(radius: SpatialTower.beaconRadius)
	static let beaconGlowMesh = MeshResource.generateSphere(radius: SpatialTower.beaconRadius * 2.2)
	static let beaconMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.1, blue: 0.08, alpha: 1))
	static let beaconGlowMaterial = SpatialSceneController.transparentMaterial(UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1), opacity: 0.45)

	static let ringMesh: MeshResource? = try? SpatialSignalRings.ringMesh().meshResource()

	/// The red light for the top of a tower: a bright core inside a faint glow, faded together.
	static func makeBeacon(height: Float) -> Entity {
		let beacon = Entity()
		beacon.position = [0, SpatialTower.beaconCenter(height: height), 0]
		beacon.addChild(ModelEntity(mesh: beaconMesh, materials: [beaconMaterial]))
		beacon.addChild(ModelEntity(mesh: beaconGlowMesh, materials: [beaconGlowMaterial]))
		beacon.components.set(OpacityComponent(opacity: 0))
		return beacon
	}
}
#endif
