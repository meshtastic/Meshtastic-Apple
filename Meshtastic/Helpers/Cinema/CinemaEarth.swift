//
//  CinemaEarth.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/10/26.
//
#if os(visionOS)
import CinemaContent
import OSLog
import RealityKit
import UIKit

/// Turns an entity about an axis in its parent's space, at a steady rate, every frame: the globe
/// behind the space station's cupola and its clouds. A rate of zero holds it still.
struct CinemaSpinComponent: Component {
	var axis: SIMD3<Float>
	var radiansPerSecond: Float
	/// The globe turns at the panel's speed; its clouds a little faster than that.
	var rateScale: Float = 1
}

struct CinemaSpinSystem: System {
	private static let query = EntityQuery(where: .has(CinemaSpinComponent.self))

	init(scene: RealityKit.Scene) {}

	func update(context: SceneUpdateContext) {
		let delta = Float(context.deltaTime)
		for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
			guard let spin = entity.components[CinemaSpinComponent.self], spin.radiansPerSecond != 0 else { continue }
			entity.orientation = simd_quatf(angle: spin.radiansPerSecond * spin.rateScale * delta, axis: spin.axis) * entity.orientation
		}
	}
}

/// Earth from the space station, as a real globe behind the cupola's windows rather than a painted
/// view: the Blue Marble ground lit by the sun with ambient light shut out, so the side away from it
/// is dark, the Black Marble's city lights on the ground by night, clouds over it, a glow of air
/// along its edge, and stars behind. Drawn to scale far out past the cupola's sphere, where
/// `CinemaOrbit` puts it, and turned by `CinemaSpinSystem` so the ground drifts past.
@MainActor
enum CinemaEarth {
	private static var registered = false

	/// The globe, its air and the stars, under one entity in the stage's axes, or nil if its
	/// textures won't load, so the painted view can be shown instead.
	static func make(side: CinemaEarthSide, radiansPerSecond: Float) async -> Entity? {
		if !registered {
			CinemaSpinComponent.registerComponent()
			CinemaSpinSystem.registerSystem()
			registered = true
		}
		guard let ground = await texture("space_earth_ground", semantic: .color),
			  let cloudCover = await opacityTexture(named: "space_earth_clouds") else {
			Logger.services.error("🎬 [Cinema] Couldn't load Earth's textures; showing the painted view")
			return nil
		}
		let root = Entity()
		root.name = "CinemaEarth"

		if let stars = await starTexture() {
			var material = UnlitMaterial(color: .black)
			material.color = .init(tint: .white, texture: .init(stars))
			let sky = ModelEntity(mesh: .generateSphere(radius: CinemaBackdrop.skyRadius), materials: [material])
			sky.name = "Stars"
			sky.scale = [-1, 1, 1]
			root.addChild(sky)
		}

		// Lit by the sun alone: ambient light from a black environment, so night is dark.
		let shade = Entity()
		shade.name = "Shade"
		if let black = await blackEnvironment() {
			shade.components.set(ImageBasedLightComponent(source: .single(black), intensityExponent: 0))
		}
		root.addChild(shade)
		let sun = DirectionalLight()
		sun.name = "Sun"
		sun.light.intensity = 3_000
		sun.light.color = UIColor(red: 1, green: 0.98, blue: 0.95, alpha: 1)
		let toward = -CinemaOrbit.sunDirection(side)
		sun.look(at: toward, from: .zero, relativeTo: root)
		root.addChild(sun)

		let center = CinemaOrbit.earthDirection * CinemaOrbit.globeDistance
		let axis = CinemaOrbit.spinAxis

		var groundMaterial = PhysicallyBasedMaterial()
		groundMaterial.baseColor = .init(tint: .white, texture: .init(ground))
		groundMaterial.roughness = 0.85
		groundMaterial.metallic = 0.0
		// City lights only by night: by day the ground under the station is all in sunlight, and
		// the lights would show through it.
		if side == .night, let lights = await texture("space_earth_lights", semantic: .color) {
			groundMaterial.emissiveColor = .init(color: .white, texture: .init(lights))
			groundMaterial.emissiveIntensity = 1.4
		}
		// Without the ground there's no Earth, so the painted one stands in.
		guard let ground = globe("Ground", radius: CinemaOrbit.globeRadius, material: groundMaterial, shade: shade) else { return nil }
		ground.position = center
		ground.orientation = CinemaOrbit.orientation
		ground.components.set(CinemaSpinComponent(axis: axis, radiansPerSecond: radiansPerSecond))
		root.addChild(ground)

		var cloudMaterial = PhysicallyBasedMaterial()
		cloudMaterial.baseColor = .init(tint: UIColor(white: 0.96, alpha: 1))
		cloudMaterial.roughness = 1.0
		cloudMaterial.blending = .transparent(opacity: .init(scale: 1, texture: .init(cloudCover)))
		if let clouds = globe("Clouds", radius: CinemaOrbit.cloudRadius, material: cloudMaterial, shade: shade) {
			clouds.position = center
			clouds.orientation = CinemaOrbit.orientation
			clouds.components.set(CinemaSpinComponent(axis: axis, radiansPerSecond: radiansPerSecond, rateScale: CinemaOrbit.cloudRate))
			clouds.components.set(ModelSortGroupComponent(group: sortGroup, order: 1))
			root.addChild(clouds)
		}

		// The air doesn't turn: its glow is where the edge is as seen from the seat, and where the sun is.
		if let glow = await airTextures(side: side) {
			var airMaterial = UnlitMaterial(color: .black)
			airMaterial.color = .init(tint: .white, texture: .init(glow.color))
			airMaterial.blending = .transparent(opacity: .init(scale: 1, texture: .init(glow.opacity)))
			if let air = globe("Air", radius: CinemaOrbit.airRadius, material: airMaterial, shade: nil) {
				air.position = center
				air.components.set(ModelSortGroupComponent(group: sortGroup, order: 2))
				root.addChild(air)
			}
		}
		return root
	}

	/// Sets how fast the globe and its clouds turn, on a backdrop holding one.
	static func setSpin(_ radiansPerSecond: Float, in backdrop: Entity) {
		guard let earth = backdrop.findEntity(named: "CinemaEarth") else { return }
		for name in ["Ground", "Clouds"] {
			guard let globe = earth.findEntity(named: name), var spin = globe.components[CinemaSpinComponent.self] else { continue }
			spin.radiansPerSecond = radiansPerSecond
			globe.components.set(spin)
		}
	}

	private static let sortGroup = ModelSortGroup(depthPass: nil)

	private static func globe(_ name: String, radius: Float, material: any RealityKit.Material, shade: Entity?) -> ModelEntity? {
		let shape = CinemaOrbit.sphere(radius: radius)
		var descriptor = MeshDescriptor(name: name)
		descriptor.positions = MeshBuffer(shape.positions)
		descriptor.normals = MeshBuffer(shape.normals)
		descriptor.textureCoordinates = MeshBuffer(shape.coordinates)
		descriptor.primitives = .triangles(shape.indices)
		do {
			let entity = ModelEntity(mesh: try MeshResource.generate(from: [descriptor]), materials: [material])
			entity.name = name
			if let shade {
				entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: shade))
			}
			return entity
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make Earth's \(name, privacy: .public) mesh: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	private static func texture(_ name: String, semantic: TextureResource.Semantic) async -> TextureResource? {
		guard let url = cinemaEnvironmentImageURL(named: name) else { return nil }
		do {
			return try await TextureResource(contentsOf: url, options: .init(semantic: semantic))
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't load \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// A gray image as an opacity texture, with the gray in every channel and in alpha, so the
	/// material reads the cover whichever channel it takes it from.
	private static func opacityTexture(named name: String) async -> TextureResource? {
		guard let url = cinemaEnvironmentImageURL(named: name),
			  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
			  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
		let width = image.width, height = image.height
		var gray = [UInt8](repeating: 0, count: width * height)
		let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
			context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
			return true
		}
		guard drawn else { return nil }
		var rgba = [UInt8](repeating: 0, count: width * height * 4)
		for i in 0..<(width * height) {
			let value = gray[i]
			rgba[i * 4] = value
			rgba[i * 4 + 1] = value
			rgba[i * 4 + 2] = value
			rgba[i * 4 + 3] = value
		}
		return await rgbaTexture(rgba, width: width, height: height, semantic: .raw)
	}

	/// The air's glow, as a color texture and an opacity texture.
	private static func airTextures(side: CinemaEarthSide) async -> (color: TextureResource, opacity: TextureResource)? {
		let width = 1024, height = 512
		let pixels = await Task.detached(priority: .userInitiated) { CinemaOrbit.airGlow(side: side, width: width) }.value
		var opacity = [UInt8](repeating: 0, count: pixels.count)
		for i in stride(from: 0, to: pixels.count, by: 4) {
			let a = pixels[i + 3]
			opacity[i] = a
			opacity[i + 1] = a
			opacity[i + 2] = a
			opacity[i + 3] = a
		}
		guard let color = await rgbaTexture(pixels, width: width, height: height, semantic: .color),
			  let alpha = await rgbaTexture(opacity, width: width, height: height, semantic: .raw) else { return nil }
		return (color, alpha)
	}

	/// A sparse field of stars on black, the same every time.
	private static func starTexture() async -> TextureResource? {
		let width = 4096, height = 2048
		// 32 MB of pixels, made off the main actor.
		let pixels = await Task.detached(priority: .userInitiated) {
			var pixels = [UInt8](repeating: 0, count: width * height * 4)
			var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
			func next() -> Double {
				seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
				return Double(seed >> 11) / Double(1 << 53)
			}
			for i in 0..<(width * height) { pixels[i * 4 + 3] = 255 }
			for _ in 0..<2_400 {
				// Spread evenly over the sphere, not bunched at the poles.
				let x = Int(next() * Double(width))
				let y = Int(acos(1 - 2 * next()) / .pi * Double(height - 1))
				let level = UInt8(60 + pow(next(), 3) * 195)
				let i = (y * width + x) * 4
				pixels[i] = level
				pixels[i + 1] = level
				pixels[i + 2] = UInt8(min(Int(level) + 12, 255))
			}
			return pixels
		}.value
		return await rgbaTexture(pixels, width: width, height: height, semantic: .color)
	}

	/// An environment that gives no light, to keep the room's ambient light off the globe.
	private static func blackEnvironment() async -> EnvironmentResource? {
		let width = 32, height = 16
		let pixels = (0..<(width * height * 4)).map { UInt8($0 % 4 == 3 ? 255 : 0) }
		guard let image = cgImage(pixels, width: width, height: height) else { return nil }
		do {
			return try await EnvironmentResource(equirectangular: image)
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make Earth's dark environment: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	private static func rgbaTexture(_ pixels: [UInt8], width: Int, height: Int, semantic: TextureResource.Semantic) async -> TextureResource? {
		guard let image = cgImage(pixels, width: width, height: height) else { return nil }
		do {
			return try await TextureResource(image: image, options: .init(semantic: semantic))
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make an Earth texture: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	private static func cgImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
		guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
		return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
	}
}
#endif
