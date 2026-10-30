//
//  CinemaBackdrop.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
#if os(visionOS)
import CinemaContent
import OSLog
import RealityKit
import UIKit

/// The world around the cinema screen: a large sphere showing the environment's image from the
/// inside, unlit so the image reads as painted. The image has its own floor, rendered from seated
/// eye height; CinemaSpace puts the sphere's center at that height. The image's center is at -Z,
/// the frame the render's anchors are written in.
@MainActor
enum CinemaBackdrop {
	static let radius: Float = 50
	/// A cutout's sky sits far out, past any terrain drawn between it and the room.
	static let skyRadius: Float = 980

	/// The sphere for `environment`, under one entity. For a cutout environment, a second sphere
	/// behind it with the sky: the one the room was lit by, or with `clearSky` the same sky with
	/// nothing below the horizon, for when terrain is drawn.
	static func make(_ environment: CinemaEnvironment, clearSky: Bool = false) async -> Entity {
		let root = Entity()
		root.name = "CinemaBackdrop"

		var roomMaterial = UnlitMaterial(color: environment.placeholderColors.horizon)
		if let texture = await texture(for: environment) {
			roomMaterial.color = .init(tint: .white, texture: .init(texture))
			if environment.isCutout {
				// The image's alpha is the glass: anything behind the sphere shows through it.
				roomMaterial.opacityThreshold = 0.4
			}
		}
		root.addChild(sphere("Room", radius: radius, material: roomMaterial))

		if environment.isCutout, let name = clearSky ? environment.clearSkyImageName : environment.skyImageName {
			var skyMaterial = UnlitMaterial(color: environment.placeholderColors.sky)
			if let texture = await texture(named: name) {
				skyMaterial.color = .init(tint: .white, texture: .init(texture))
			}
			root.addChild(sphere("Sky", radius: skyRadius, material: skyMaterial))
		}
		return root
	}

	/// A sphere seen from inside, with the image's center at -Z.
	private static func sphere(_ name: String, radius: Float, material: UnlitMaterial) -> ModelEntity {
		let sphere = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
		sphere.name = name
		// Turned inside out so the faces point at the viewer in the middle.
		sphere.scale = [-1, 1, 1]
		// A RealityKit sphere puts the image's center a quarter turn to the right; this brings it
		// to -Z. Fixed for every image; CinemaSpace turns the whole backdrop.
		sphere.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
		return sphere
	}

	/// The environment's image, or a gradient from its sky to its ground if the image won't load.
	private static func texture(for environment: CinemaEnvironment) async -> TextureResource? {
		if let texture = await texture(named: environment.imageName) {
			return texture
		}
		guard let image = placeholderImage(environment.placeholderColors) else { return nil }
		do {
			return try await TextureResource(image: image, options: .init(semantic: .color))
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make the backdrop texture: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// An image from CinemaContent as a texture, or nil if it won't load.
	private static func texture(named name: String) async -> TextureResource? {
		guard let url = cinemaEnvironmentImageURL(named: name) else { return nil }
		do {
			return try await TextureResource(contentsOf: url, options: .init(semantic: .color))
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't load \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
