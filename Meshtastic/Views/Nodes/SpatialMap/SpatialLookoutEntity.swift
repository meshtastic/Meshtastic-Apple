//
//  SpatialLookoutEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
#if os(visionOS)
import RealityKit
import UIKit

/// The fire lookout as an entity: one model per material, built once and reused.
@MainActor
enum SpatialLookoutParts {
	private static var meshes: [SpatialLookout.Part: MeshResource]?

	static func make() -> Entity? {
		if meshes == nil {
			var built: [SpatialLookout.Part: MeshResource] = [:]
			for (part, data) in SpatialLookout.geometry() where data.triangleCount > 0 {
				guard let mesh = try? data.meshResource() else { return nil }
				built[part] = mesh
			}
			meshes = built
		}
		guard let meshes else { return nil }
		let lookout = Entity()
		lookout.name = "fireLookout"
		let body = Entity()
		body.orientation = simd_quatf(angle: SpatialLookout.yaw, axis: [0, 1, 0])
		for part in SpatialLookout.Part.allCases {
			guard let mesh = meshes[part] else { continue }
			body.addChild(ModelEntity(mesh: mesh, materials: [material(part)]))
		}
		lookout.addChild(body)
		return lookout
	}

	private static func material(_ part: SpatialLookout.Part) -> PhysicallyBasedMaterial {
		var material = PhysicallyBasedMaterial()
		switch part {
		case .stone:
			material.baseColor = .init(tint: UIColor(red: 0.55, green: 0.53, blue: 0.5, alpha: 1))
			material.roughness = 0.9
		case .wall:
			material.baseColor = .init(tint: UIColor(red: 0.93, green: 0.9, blue: 0.82, alpha: 1))
			material.roughness = 0.7
		case .glass:
			// Dark glass with a little lamplight behind it.
			material.baseColor = .init(tint: UIColor(red: 0.1, green: 0.14, blue: 0.18, alpha: 1))
			material.emissiveColor = .init(color: UIColor(red: 1, green: 0.72, blue: 0.4, alpha: 1))
			material.emissiveIntensity = 0.15
			material.roughness = 0.1
			material.metallic = 0.3
		case .roof:
			material.baseColor = .init(tint: UIColor(red: 0.2, green: 0.33, blue: 0.22, alpha: 1))
			material.roughness = 0.6
		case .wood:
			material.baseColor = .init(tint: UIColor(red: 0.45, green: 0.3, blue: 0.18, alpha: 1))
			material.roughness = 0.85
		case .metal:
			material.baseColor = .init(tint: UIColor(white: 0.8, alpha: 1))
			material.metallic = 0.8
			material.roughness = 0.3
		}
		return material
	}
}
#endif
