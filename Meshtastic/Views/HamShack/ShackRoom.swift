//
//  ShackRoom.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import CoreGraphics
import OSLog
import RealityKit
import ShackContent
import UIKit

/// The ham shack room: the Shack.usda scene from ShackContent, with its lights added, and where
/// each named anchor ended up. Anchors the asset lacks come from `ShackRoomGeometry`.
@MainActor
struct ShackRoom {
	/// Place at the space's origin; the room is authored with the viewer's seat there.
	let root: Entity
	let anchors: [ShackAnchor: ShackAnchorPose]
	/// Anchors the asset did not have, placed from the defaults instead.
	let missingAnchors: [ShackAnchor]
	/// False when the asset failed to load and a plain stand-in room was built.
	let loadedAsset: Bool

	func pose(_ anchor: ShackAnchor) -> ShackAnchorPose {
		anchors[anchor] ?? ShackRoomGeometry.defaultPose(anchor)
	}

	static func load() async -> ShackRoom {
		let root = Entity()
		root.name = "ShackRoom"
		var found: [String: ShackAnchorPose] = [:]
		var loadedAsset = false
		do {
			let scene = try await Entity(named: ShackRoomGeometry.assetName, in: shackContentBundle)
			root.addChild(scene)
			for anchor in ShackAnchor.allCases {
				guard let entity = scene.findEntity(named: anchor.rawValue) else { continue }
				found[anchor.rawValue] = ShackAnchorPose(
					entity.position(relativeTo: root),
					orientation: entity.orientation(relativeTo: root)
				)
			}
			loadedAsset = true
		} catch {
			Logger.services.error("📻 [Shack] The room failed to load: \(error.localizedDescription, privacy: .public)")
			root.addChild(standInRoom())
		}
		let resolved = ShackRoomGeometry.resolve(found: found)
		if loadedAsset, !resolved.missing.isEmpty {
			Logger.services.warning("📻 [Shack] Room is missing anchors: \(resolved.missing.map(\.rawValue).joined(separator: ", "), privacy: .public)")
		}
		let room = ShackRoom(root: root, anchors: resolved.poses, missingAnchors: resolved.missing, loadedAsset: loadedAsset)
		room.drawSkyUnlit()
		await room.addLighting()
		return room
	}

	// MARK: Materials

	/// The sky outside the window keeps its own colors, whatever the lamp does.
	private func drawSkyUnlit() {
		guard let sky = root.findEntity(named: "Sky") else { return }
		for entity in Self.modelEntities(in: sky) {
			guard var model = entity.components[ModelComponent.self] else { continue }
			model.materials = model.materials.map { material in
				guard let texture = (material as? PhysicallyBasedMaterial)?.baseColor.texture else { return material }
				var unlit = UnlitMaterial()
				unlit.color = .init(tint: .white, texture: texture)
				return unlit
			}
			entity.components.set(model)
		}
	}

	// MARK: Lighting

	/// The entity carrying the room's image-based light; things added later receive it too.
	static let environmentLightName = "ShackEnvironment"

	private static let lampColor = UIColor(red: 1.0, green: 0.78, blue: 0.52, alpha: 1)

	/// A warm point light at the lamp's bulb, a spot from the lamp onto the desk with shadows, a
	/// dim fill from behind the viewer, and a warm environment for reflections.
	private func addLighting() async {
		let lamp = pose(.lamp)

		let bulb = Entity()
		bulb.name = "LampLight"
		bulb.position = lamp.position
		bulb.components.set(PointLightComponent(color: Self.lampColor, intensity: 2200, attenuationRadius: 4))
		root.addChild(bulb)

		let spot = Entity()
		spot.name = "LampSpot"
		root.addChild(spot)
		let target = pose(.deskMap).position + SIMD3<Float>(0.1, 0, 0.05)
		spot.look(at: target, from: lamp.position, relativeTo: root)
		spot.components.set(SpotLightComponent(color: Self.lampColor, intensity: 5000, innerAngleInDegrees: 50, outerAngleInDegrees: 110, attenuationRadius: 3))
		spot.components.set(SpotLightComponent.Shadow())

		let fill = Entity()
		fill.name = "CeilingFill"
		fill.position = SIMD3<Float>(0.2, 1.9, 0.8)
		fill.components.set(PointLightComponent(color: UIColor(red: 1.0, green: 0.86, blue: 0.70, alpha: 1), intensity: 700, attenuationRadius: 5))
		root.addChild(fill)

		guard let image = Self.environmentImage(),
			  let environment = try? await EnvironmentResource(equirectangular: image, withName: "ShackEnvironment") else { return }
		let light = Entity()
		light.name = Self.environmentLightName
		light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: -1.5))
		root.addChild(light)
		for entity in Self.modelEntities(in: root) {
			entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
		}
	}

	/// A small equirectangular image of a warm, dim room: lamp-lit walls around the horizon, a
	/// darker ceiling, and the floor's brown below.
	private static func environmentImage() -> CGImage? {
		let width = 64, height = 32
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
			let format = UIGraphicsImageRendererFormat()
			format.scale = 1
			return format
		}())
		let image = renderer.image { context in
			let colors = [
				UIColor(red: 0.30, green: 0.26, blue: 0.22, alpha: 1).cgColor,
				UIColor(red: 0.85, green: 0.66, blue: 0.45, alpha: 1).cgColor,
				UIColor(red: 0.62, green: 0.46, blue: 0.32, alpha: 1).cgColor,
				UIColor(red: 0.20, green: 0.12, blue: 0.07, alpha: 1).cgColor
			] as CFArray
			guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 0.55, 1]) else { return }
			context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
		}
		return image.cgImage
	}

	// MARK: Helpers

	private static func modelEntities(in entity: Entity) -> [Entity] {
		var result: [Entity] = entity.components.has(ModelComponent.self) ? [entity] : []
		for child in entity.children {
			result += modelEntities(in: child)
		}
		return result
	}

	/// A plain floor, back wall and desk at the asset's measurements, for when Shack.usda fails
	/// to load, so the shack still has somewhere to put things.
	private static func standInRoom() -> Entity {
		let room = Entity()
		room.name = "StandInRoom"
		let floor = ModelEntity(
			mesh: .generateBox(width: ShackRoomGeometry.width, height: 0.02, depth: ShackRoomGeometry.width),
			materials: [SimpleMaterial(color: UIColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1), roughness: 0.6, isMetallic: false)]
		)
		floor.position = SIMD3<Float>(0, -0.01, ShackRoomGeometry.backWallZ + ShackRoomGeometry.width / 2)
		let wall = ModelEntity(
			mesh: .generateBox(width: ShackRoomGeometry.width, height: ShackRoomGeometry.height, depth: 0.06),
			materials: [SimpleMaterial(color: UIColor(red: 0.58, green: 0.52, blue: 0.42, alpha: 1), roughness: 0.9, isMetallic: false)]
		)
		wall.position = SIMD3<Float>(0, ShackRoomGeometry.height / 2, ShackRoomGeometry.backWallZ - 0.03)
		let desk = ModelEntity(
			mesh: .generateBox(width: 1.9, height: 0.04, depth: 0.75),
			materials: [SimpleMaterial(color: UIColor(red: 0.26, green: 0.15, blue: 0.08, alpha: 1), roughness: 0.45, isMetallic: false)]
		)
		desk.position = SIMD3<Float>(0, ShackRoomGeometry.deskTopY - 0.02, ShackRoomGeometry.backWallZ + 0.375)
		room.addChild(floor)
		room.addChild(wall)
		room.addChild(desk)
		return room
	}
}
#endif
