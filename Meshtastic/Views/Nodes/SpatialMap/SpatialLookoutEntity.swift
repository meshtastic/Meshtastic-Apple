//
//  SpatialLookoutEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
#if os(visionOS)
import Metal
import OSLog
import RealityKit
import UIKit

/// The fire lookout, the castle tower, the lighthouse, the city rooftop's water tower and mast,
/// the space station and the sky deck, as entities: one model per material, built once and reused.
@MainActor
enum SpatialLookoutParts {
	private static var meshes: [SpatialLookout.Part: MeshResource]?

	/// The lookout with its cab facing `heading`.
	static func make(heading: Double = SpatialLookout.frontHeading) -> Entity? {
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
		body.orientation = simd_quatf(angle: SpatialLookout.yaw(heading: heading), axis: [0, 1, 0])
		for part in SpatialLookout.Part.allCases {
			guard let mesh = meshes[part] else { continue }
			body.addChild(ModelEntity(mesh: mesh, materials: [material(part)]))
		}
		lookout.addChild(body)
		return lookout
	}

	/// The castle tower in `stone`, its front facing `heading`, for the castle room.
	static func makeCastle(heading: Double = SpatialLookout.frontHeading, stone: CastleStone) -> Entity? {
		if castleMeshes == nil {
			var built: [SpatialCastle.Part: MeshResource] = [:]
			for (part, data) in SpatialCastle.geometry() where data.triangleCount > 0 {
				var descriptor = MeshDescriptor()
				descriptor.positions = MeshBuffers.Positions(data.positions)
				descriptor.normals = MeshBuffers.Normals(data.normals)
				if part == .stone {
					descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(SpatialCastle.textureCoordinates(data))
				}
				descriptor.primitives = .triangles(data.indices)
				do {
					built[part] = try MeshResource.generate(from: [descriptor])
				} catch {
					Logger.services.error("🏰 [SpatialMap] Couldn't make the castle's \(String(describing: part), privacy: .public) mesh: \(error.localizedDescription, privacy: .public)")
					return nil
				}
			}
			castleMeshes = built
		}
		guard let castleMeshes else { return nil }
		let castle = Entity()
		castle.name = "castleTower"
		let body = Entity()
		body.orientation = simd_quatf(angle: SpatialLookout.yaw(heading: heading), axis: [0, 1, 0])
		for part in SpatialCastle.Part.allCases {
			guard let mesh = castleMeshes[part] else { continue }
			body.addChild(ModelEntity(mesh: mesh, materials: [castleMaterial(part, stone: stone)]))
		}
		castle.addChild(body)
		return castle
	}

	/// The sky deck's glass box, opening out along `heading`, for the sky deck room.
	static func makeSkyDeck(heading: Double = SpatialLookout.frontHeading) -> Entity? {
		if skyDeckMeshes == nil {
			var built: [SpatialSkyDeck.Part: MeshResource] = [:]
			for (part, data) in SpatialSkyDeck.geometry() where data.triangleCount > 0 {
				guard let mesh = try? data.meshResource() else { return nil }
				built[part] = mesh
			}
			skyDeckMeshes = built
		}
		guard let skyDeckMeshes else { return nil }
		let deck = Entity()
		deck.name = "skyDeck"
		let body = Entity()
		body.orientation = simd_quatf(angle: SpatialLookout.yaw(heading: heading), axis: [0, 1, 0])
		for part in SpatialSkyDeck.Part.allCases {
			guard let mesh = skyDeckMeshes[part] else { continue }
			body.addChild(ModelEntity(mesh: mesh, materials: [skyDeckMaterial(part)]))
		}
		deck.addChild(body)
		return deck
	}

	private static var skyDeckMeshes: [SpatialSkyDeck.Part: MeshResource]?

	private static func skyDeckMaterial(_ part: SpatialSkyDeck.Part) -> PhysicallyBasedMaterial {
		var material = PhysicallyBasedMaterial()
		switch part {
		case .glass:
			// Pale blue and see-through, a little lit from inside, so it reads against the gray tower.
			material.baseColor = .init(tint: UIColor(red: 0.62, green: 0.82, blue: 0.95, alpha: 1))
			material.emissiveColor = .init(color: UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1))
			material.emissiveIntensity = 0.25
			material.roughness = 0.1
			material.metallic = 0.2
			material.blending = .transparent(opacity: 0.5)
		case .frame:
			material.baseColor = .init(tint: UIColor(red: 0.2, green: 0.21, blue: 0.23, alpha: 1))
			material.metallic = 0.6
			material.roughness = 0.4
		case .ceiling:
			// The ceiling's downlights.
			material.baseColor = .init(tint: UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1))
			material.emissiveColor = .init(color: UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1))
			material.emissiveIntensity = 0.8
		}
		return material
	}

	/// The city rooftop's water tower and mast, their front facing `heading`, for the rooftop room.
	static func makeRooftop(heading: Double = SpatialLookout.frontHeading) -> Entity? {
		if rooftopMeshes == nil {
			var built: [SpatialRooftop.Part: MeshResource] = [:]
			for (part, data) in SpatialRooftop.geometry() where data.triangleCount > 0 {
				guard let mesh = try? data.meshResource() else { return nil }
				built[part] = mesh
			}
			rooftopMeshes = built
		}
		guard let rooftopMeshes else { return nil }
		let rooftop = Entity()
		rooftop.name = "cityRooftop"
		let body = Entity()
		body.orientation = simd_quatf(angle: SpatialLookout.yaw(heading: heading), axis: [0, 1, 0])
		for part in SpatialRooftop.Part.allCases {
			guard let mesh = rooftopMeshes[part] else { continue }
			body.addChild(ModelEntity(mesh: mesh, materials: [rooftopMaterial(part)]))
		}
		rooftop.addChild(body)
		return rooftop
	}

	private static var rooftopMeshes: [SpatialRooftop.Part: MeshResource]?

	private static func rooftopMaterial(_ part: SpatialRooftop.Part) -> PhysicallyBasedMaterial {
		var material = PhysicallyBasedMaterial()
		switch part {
		// Light, like the water tower on the cinema's deck, so it reads against the gray buildings.
		case .staves:
			material.baseColor = .init(tint: UIColor(red: 0.72, green: 0.56, blue: 0.4, alpha: 1))
			material.roughness = 0.8
		case .roof:
			material.baseColor = .init(tint: UIColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1))
			material.metallic = 0.3
			material.roughness = 0.5
		case .steel:
			material.baseColor = .init(tint: UIColor(red: 0.68, green: 0.69, blue: 0.7, alpha: 1))
			material.metallic = 0.5
			material.roughness = 0.4
		}
		return material
	}

	/// The lighthouse with its lantern's front facing `heading`, for the lighthouse room.
	static func makeLighthouse(heading: Double = SpatialLookout.frontHeading) -> Entity? {
		if lighthouseMeshes == nil {
			var built: [SpatialLighthouse.Part: MeshResource] = [:]
			for (part, data) in SpatialLighthouse.geometry() where data.triangleCount > 0 {
				do {
					built[part] = try data.meshResource()
				} catch {
					Logger.services.error("🗼 [SpatialMap] Couldn't make the lighthouse's \(String(describing: part), privacy: .public) mesh: \(error.localizedDescription, privacy: .public)")
					return nil
				}
			}
			lighthouseMeshes = built
		}
		guard let lighthouseMeshes else { return nil }
		let lighthouse = Entity()
		lighthouse.name = "lighthouse"
		let body = Entity()
		body.orientation = simd_quatf(angle: SpatialLookout.yaw(heading: heading), axis: [0, 1, 0])
		for part in SpatialLighthouse.Part.allCases {
			guard let mesh = lighthouseMeshes[part] else { continue }
			body.addChild(ModelEntity(mesh: mesh, materials: [lighthouseMaterial(part)]))
		}
		lighthouse.addChild(body)
		return lighthouse
	}

	private static var lighthouseMeshes: [SpatialLighthouse.Part: MeshResource]?

	private static func lighthouseMaterial(_ part: SpatialLighthouse.Part) -> PhysicallyBasedMaterial {
		var material = PhysicallyBasedMaterial()
		switch part {
		case .tower:
			material.baseColor = .init(tint: UIColor(white: 0.95, alpha: 1))
			material.roughness = 0.75
		case .stone:
			material.baseColor = .init(tint: UIColor(red: 0.55, green: 0.53, blue: 0.5, alpha: 1))
			material.roughness = 0.9
		case .opening:
			material.baseColor = .init(tint: UIColor(white: 0.08, alpha: 1))
			material.roughness = 1.0
		case .iron:
			material.baseColor = .init(tint: UIColor(red: 0.08, green: 0.1, blue: 0.09, alpha: 1))
			material.roughness = 0.5
		case .glass:
			// The lamp lit behind the lantern's glass.
			material.baseColor = .init(tint: UIColor(red: 0.2, green: 0.2, blue: 0.18, alpha: 1))
			material.emissiveColor = .init(color: UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1))
			material.emissiveIntensity = 0.9
			material.roughness = 0.1
			material.metallic = 0.3
		case .dome:
			material.baseColor = .init(tint: UIColor(red: 0.62, green: 0.08, blue: 0.06, alpha: 1))
			material.roughness = 0.45
		case .metal:
			material.baseColor = .init(tint: UIColor(white: 0.8, alpha: 1))
			material.metallic = 0.8
			material.roughness = 0.3
		}
		return material
	}

	private static var castleMeshes: [SpatialCastle.Part: MeshResource]?
	private static var stationMeshes: [SpatialStation.Part: MeshResource]?

	/// The space station that floats over the map while the cinema's room is the station.
	static func makeStation() -> Entity? {
		if stationMeshes == nil {
			var built: [SpatialStation.Part: MeshResource] = [:]
			for (part, data) in SpatialStation.geometry() where data.triangleCount > 0 {
				var descriptor = MeshDescriptor()
				descriptor.positions = MeshBuffers.Positions(data.positions)
				descriptor.normals = MeshBuffers.Normals(data.normals)
				descriptor.primitives = .triangles(data.indices)
				do {
					built[part] = try MeshResource.generate(from: [descriptor])
				} catch {
					Logger.services.error("🛰️ [SpatialMap] Couldn't make the space station's \(String(describing: part), privacy: .public) mesh: \(error.localizedDescription, privacy: .public)")
					return nil
				}
			}
			stationMeshes = built
		}
		guard let stationMeshes else { return nil }
		let station = Entity()
		station.name = "spaceStationBody"
		for part in SpatialStation.Part.allCases {
			guard let mesh = stationMeshes[part] else { continue }
			station.addChild(ModelEntity(mesh: mesh, materials: [stationMaterial(part)]))
		}
		return station
	}

	private static func stationMaterial(_ part: SpatialStation.Part) -> PhysicallyBasedMaterial {
		var material = PhysicallyBasedMaterial()
		switch part {
		case .truss:
			material.baseColor = .init(tint: UIColor(white: 0.72, alpha: 1))
			material.metallic = 0.6
			material.roughness = 0.45
		case .solar:
			// The wings' amber, as they look in sunlight.
			material.baseColor = .init(tint: UIColor(red: 0.62, green: 0.43, blue: 0.17, alpha: 1))
			material.metallic = 0.35
			material.roughness = 0.35
		case .rollout:
			// The newer cells' deep blue, with the sheen of glass over them.
			material.baseColor = .init(tint: UIColor(red: 0.1, green: 0.13, blue: 0.27, alpha: 1))
			material.metallic = 0.4
			material.roughness = 0.25
		case .radiator:
			material.baseColor = .init(tint: UIColor(white: 0.95, alpha: 1))
			material.roughness = 0.7
		case .arm:
			material.baseColor = .init(tint: UIColor(white: 0.93, alpha: 1))
			material.roughness = 0.5
		case .dark:
			material.baseColor = .init(tint: UIColor(white: 0.22, alpha: 1))
			material.metallic = 0.5
			material.roughness = 0.5
		case .logo:
			// Meshtastic green, glowing a little so it reads in the station's shade.
			material.baseColor = .init(tint: UIColor(red: 103 / 255, green: 234 / 255, blue: 148 / 255, alpha: 1))
			material.emissiveColor = .init(color: UIColor(red: 103 / 255, green: 234 / 255, blue: 148 / 255, alpha: 1))
			material.emissiveIntensity = 0.3
			material.roughness = 0.4
		case .module:
			material.baseColor = .init(tint: UIColor(red: 0.9, green: 0.9, blue: 0.87, alpha: 1))
			material.roughness = 0.6
		case .window:
			// Dark glass with the module's light behind it.
			material.baseColor = .init(tint: UIColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1))
			material.emissiveColor = .init(color: UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1))
			material.emissiveIntensity = 0.5
			material.roughness = 0.1
		}
		return material
	}
	private static var blockTexture: TextureResource?

	/// Dressed stone blocks in running bond, `SpatialCastle.tileBlocks` across and up, with pale
	/// mortar joints, each block a little lighter or darker than the next. Drawn in white and gray;
	/// the material tints it with the stone's color.
	private static func blocks() -> TextureResource? {
		if let blockTexture { return blockTexture }
		let count = SpatialCastle.tileBlocks
		let blockSize = CGSize(width: 128, height: 64)
		let size = CGSize(width: blockSize.width * CGFloat(count), height: blockSize.height * CGFloat(count))
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		var random = SystemRandomNumberGenerator()
		let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
			UIColor(white: 0.97, alpha: 1).setFill()
			context.fill(CGRect(origin: .zero, size: size))
			let joint: CGFloat = 7
			for course in 0..<count {
				let shift = course.isMultiple(of: 2) ? 0 : blockSize.width / 2
				// One more block than fit, so the shifted courses wrap round the tile's edge.
				for index in -1..<count {
					let rect = CGRect(x: shift + CGFloat(index) * blockSize.width, y: CGFloat(course) * blockSize.height, width: blockSize.width, height: blockSize.height)
						.insetBy(dx: joint / 2, dy: joint / 2)
					UIColor(white: CGFloat.random(in: 0.7...0.88, using: &random), alpha: 1).setFill()
					context.fill(rect)
					// A darker lower edge, as if each block's face caught the light from above.
					UIColor(white: 0, alpha: 0.12).setFill()
					context.fill(CGRect(x: rect.minX, y: rect.maxY - 6, width: rect.width, height: 6))
				}
			}
		}
		guard let cgImage = image.cgImage else { return nil }
		do {
			blockTexture = try TextureResource(image: cgImage, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
		} catch {
			Logger.services.error("🏰 [SpatialMap] Couldn't make the castle's block texture: \(error.localizedDescription, privacy: .public)")
		}
		return blockTexture
	}

	private static func castleMaterial(_ part: SpatialCastle.Part, stone: CastleStone) -> PhysicallyBasedMaterial {
		var material = PhysicallyBasedMaterial()
		switch part {
		case .stone:
			// The stone of the castle room's image.
			let color = switch stone {
			// Brighter than the stone itself, since the blocks' texture darkens it.
			case .gray: UIColor(red: 0.76, green: 0.75, blue: 0.71, alpha: 1)
			case .pink: UIColor(red: 1, green: 0.42, blue: 0.75, alpha: 1)
			}
			if let blocks = blocks() {
				// Tiled up the walls, and mipmapped so the joints don't shimmer when the castle is small.
				let sampler = MTLSamplerDescriptor()
				sampler.sAddressMode = .repeat
				sampler.tAddressMode = .repeat
				sampler.minFilter = .linear
				sampler.magFilter = .linear
				sampler.mipFilter = .linear
				material.baseColor = .init(tint: color, texture: .init(blocks, sampler: .init(sampler)))
			} else {
				material.baseColor = .init(tint: color)
			}
			material.roughness = 0.9
		case .opening:
			material.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1))
			material.roughness = 1.0
		case .window:
			// Dark leaded glass with firelight behind it.
			material.baseColor = .init(tint: UIColor(red: 0.1, green: 0.09, blue: 0.08, alpha: 1))
			material.emissiveColor = .init(color: UIColor(red: 1, green: 0.66, blue: 0.3, alpha: 1))
			material.emissiveIntensity = 0.45
			material.roughness = 0.15
			material.metallic = 0.3
		case .wood:
			material.baseColor = .init(tint: UIColor(red: 0.3, green: 0.19, blue: 0.1, alpha: 1))
			material.roughness = 0.85
		case .banner:
			// Meshtastic charcoal.
			material.baseColor = .init(tint: UIColor(red: 0.17, green: 0.18, blue: 0.24, alpha: 1))
			material.roughness = 0.9
		case .metal:
			material.baseColor = .init(tint: UIColor(red: 0.75, green: 0.6, blue: 0.25, alpha: 1))
			material.metallic = 0.9
			material.roughness = 0.35
		}
		return material
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
