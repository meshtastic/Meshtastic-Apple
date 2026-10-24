//
//  CinemaBackdrop.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
#if os(visionOS)
import OSLog
import RealityKit
import UIKit

/// The world around the cinema screen: a large sphere showing the environment's image from the
/// inside, unlit so the image reads as painted, and a floor under the viewer.
@MainActor
enum CinemaBackdrop {
	static let radius: Float = 50

	/// The sphere and the floor for `environment`, parented to one entity.
	static func make(_ environment: CinemaEnvironment) async -> Entity {
		let root = Entity()
		root.name = "CinemaBackdrop"

		var skyMaterial = UnlitMaterial(color: environment.placeholderColors.horizon)
		if let texture = await texture(for: environment) {
			skyMaterial.color = .init(tint: .white, texture: .init(texture))
		}
		let sky = ModelEntity(mesh: .generateSphere(radius: radius), materials: [skyMaterial])
		sky.name = "Sky"
		// Turned inside out so the faces point at the viewer in the middle.
		sky.scale = [-1, 1, 1]
		root.addChild(sky)

		let floor = ModelEntity(
			mesh: .generateCylinder(height: 0.01, radius: 20),
			materials: [UnlitMaterial(color: environment.floorColor)]
		)
		floor.name = "Floor"
		floor.position = [0, -0.005, 0]
		root.addChild(floor)
		return root
	}

	/// The environment's image. Until the real images are in the app this is a gradient from the
	/// environment's sky to its ground.
	private static func texture(for environment: CinemaEnvironment) async -> TextureResource? {
		guard let image = placeholderImage(environment.placeholderColors) else { return nil }
		do {
			return try await TextureResource(image: image, options: .init(semantic: .color))
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make the backdrop texture: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	private static func placeholderImage(_ colors: (sky: UIColor, horizon: UIColor, ground: UIColor)) -> CGImage? {
		let size = CGSize(width: 1024, height: 512)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
			let space = CGColorSpaceCreateDeviceRGB()
			let gradientColors = [colors.sky.cgColor, colors.horizon.cgColor, colors.ground.cgColor] as CFArray
			guard let gradient = CGGradient(colorsSpace: space, colors: gradientColors, locations: [0, 0.5, 0.56]) else { return }
			context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
		}
		return image.cgImage
	}
}
#endif
