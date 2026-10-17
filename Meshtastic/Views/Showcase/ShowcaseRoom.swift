//
//  ShowcaseRoom.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import CoreGraphics
import OSLog
import RealityKit
import ShowcaseContent
import UIKit

/// The showcase room: the Showcase.usda scene from ShowcaseContent, with its lights added, and where
/// each named anchor ended up. Anchors the asset lacks come from `ShowcaseRoomGeometry`.
@MainActor
struct ShowcaseRoom {
	/// Place at the space's origin; the room is authored with the viewer's seat there.
	let root: Entity
	let anchors: [ShowcaseAnchor: ShowcaseAnchorPose]
	/// Anchors the asset did not have, placed from the defaults instead.
	let missingAnchors: [ShowcaseAnchor]
	/// False when the asset failed to load and a plain stand-in room was built.
	let loadedAsset: Bool

	func pose(_ anchor: ShowcaseAnchor) -> ShowcaseAnchorPose {
		anchors[anchor] ?? ShowcaseRoomGeometry.defaultPose(anchor)
	}

	static func load() async -> ShowcaseRoom {
		let root = Entity()
		root.name = "ShowcaseRoom"
		var found: [String: ShowcaseAnchorPose] = [:]
		var loadedAsset = false
		do {
			let scene = try await Entity(named: ShowcaseRoomGeometry.assetName, in: showcaseContentBundle)
			root.addChild(scene)
			for anchor in ShowcaseAnchor.allCases {
				guard let entity = scene.findEntity(named: anchor.rawValue) else { continue }
				found[anchor.rawValue] = ShowcaseAnchorPose(
					entity.position(relativeTo: root),
					orientation: entity.orientation(relativeTo: root)
				)
			}
			loadedAsset = true
		} catch {
			Logger.services.error("📻 [Showcase] The room failed to load: \(error.localizedDescription, privacy: .public)")
			root.addChild(standInRoom())
		}
		let resolved = ShowcaseRoomGeometry.resolve(found: found)
		if loadedAsset, !resolved.missing.isEmpty {
			Logger.services.warning("📻 [Showcase] Room is missing anchors: \(resolved.missing.map(\.rawValue).joined(separator: ", "), privacy: .public)")
		}
		let room = ShowcaseRoom(root: root, anchors: resolved.poses, missingAnchors: resolved.missing, loadedAsset: loadedAsset)
		// Before the lighting, so the art gets the room's light too.
		await room.addWallArt()
		await room.addLighting()
		return room
	}

	// MARK: Lighting

	/// The entity carrying the room's image-based light; things added later receive it too.
	static let environmentLightName = "ShowcaseEnvironment"

	private static let storeWhite = UIColor(red: 1.0, green: 0.97, blue: 0.93, alpha: 1)

	/// Soft store light, kept well down so the room isn't glaring: a soft key from overhead that casts the models' shadows on the
	/// tables, a light over each table, and the room's colors for reflections.
	private func addLighting() async {
		let key = Entity()
		key.name = "KeyLight"
		root.addChild(key)
		key.look(at: pose(.table3).position, from: SIMD3<Float>(-0.6, 2.7, 0.4), relativeTo: root)
		key.components.set(DirectionalLightComponent(color: Self.storeWhite, intensity: 450))
		key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 4, depthBias: 2))

		// One over each table, each dimmer than the two the room had, so five keep about the same light.
		for anchor in ShowcaseRoomGeometry.tables {
			let light = Entity()
			light.name = "TableLight_\(anchor.rawValue)"
			light.position = pose(anchor).position + SIMD3<Float>(0, 1.6, 0.1)
			light.components.set(PointLightComponent(color: Self.storeWhite, intensity: 650, attenuationRadius: 4))
			root.addChild(light)
		}

		// Only the tables and what stands on them cast shadows; the ceiling, walls and floor
		// would otherwise put the whole room in the key light's shadow.
		for entity in Self.modelEntities(in: root) where !entity.name.contains("Table") {
			entity.components.set(DynamicLightShadowComponent(castsShadow: false))
		}

		guard let image = Self.environmentImage(),
			  let environment = try? await EnvironmentResource(equirectangular: image, withName: "ShowcaseEnvironment") else { return }
		let light = Entity()
		light.name = Self.environmentLightName
		light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: -2))
		root.addChild(light)
		for entity in Self.modelEntities(in: root) {
			entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
		}
	}

	/// A small equirectangular image of the room: a glowing white ceiling, Meshtastic green walls
	/// around the horizon, and the pale floor below.
	private static func environmentImage() -> CGImage? {
		let width = 64, height = 32
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
			let format = UIGraphicsImageRendererFormat()
			format.scale = 1
			return format
		}())
		let image = renderer.image { context in
			let colors = [
				UIColor(white: 1.0, alpha: 1).cgColor,
				UIColor(red: 0.40, green: 0.92, blue: 0.58, alpha: 1).cgColor,
				UIColor(red: 0.36, green: 0.84, blue: 0.53, alpha: 1).cgColor,
				UIColor(red: 0.74, green: 0.72, blue: 0.68, alpha: 1).cgColor
			] as CFArray
			guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 0.55, 1]) else { return }
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

	/// A plain floor, back wall and the display tables at the asset's measurements, for when
	/// Showcase.usda fails to load, so the showcase still has somewhere to put things.
	private static func standInRoom() -> Entity {
		let room = Entity()
		room.name = "StandInRoom"
		let depth = -ShowcaseRoomGeometry.backWallZ + 1
		let floor = ModelEntity(
			mesh: .generateBox(width: ShowcaseRoomGeometry.width, height: 0.02, depth: depth),
			materials: [SimpleMaterial(color: UIColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 1), roughness: 0.35, isMetallic: false)]
		)
		floor.position = SIMD3<Float>(0, -0.01, (ShowcaseRoomGeometry.backWallZ + 1) / 2)
		let wall = ModelEntity(
			mesh: .generateBox(width: ShowcaseRoomGeometry.width, height: ShowcaseRoomGeometry.height, depth: 0.06),
			materials: [SimpleMaterial(color: UIColor(red: 0.404, green: 0.918, blue: 0.580, alpha: 1), roughness: 0.85, isMetallic: false)]
		)
		wall.position = SIMD3<Float>(0, ShowcaseRoomGeometry.height / 2, ShowcaseRoomGeometry.backWallZ - 0.03)
		room.addChild(floor)
		room.addChild(wall)
		for anchor in ShowcaseRoomGeometry.tables {
			let top = ShowcaseRoomGeometry.defaultPose(anchor).position
			let table = ModelEntity(
				mesh: .generateBox(width: 1.9, height: ShowcaseRoomGeometry.tableThickness, depth: ShowcaseRoomGeometry.tableDepth),
				materials: [SimpleMaterial(color: UIColor(red: 0.84, green: 0.70, blue: 0.52, alpha: 1), roughness: 0.45, isMetallic: false)]
			)
			table.name = "StandInTable"
			table.position = top - SIMD3<Float>(0, ShowcaseRoomGeometry.tableThickness / 2, 0)
			room.addChild(table)
		}
		return room
	}
}
#endif
