//
//  CinemaModelStand.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/26/26.
//
#if os(visionOS)
import CinemaContent
import ImageIO
import OSLog
import RealityKit

/// A device model on a clear stand in front of the viewer in the cinema, from "View in your space"
/// on a 3D model: at real size and within reach, to pick up and turn over like the showcase's
/// models. Its live readings hang beside it, and a bar under it moves the lot. It stands in the air
/// rather than on something in the image: the image is painted far away, so a real-size model on a
/// painted table would float.
@MainActor
final class CinemaModelStand {
	let root = Entity()
	/// Pinch and drag to move the stand, the model and its readings.
	private let grabber = CinemaModelStand.makeGrabber()
	/// The model on its stand and its light, emptied for the next model. The readings hang from the
	/// grabber, so a new model doesn't take them down.
	private let shelf = Entity()
	private var light: Entity?
	/// The model's height on its stand, for hanging the readings beside it.
	private var standHeight: Float = 0
	/// The readings card, placed again once the model's height is known.
	private var tag: Entity?

	/// In front of the seat and to the left, clear of the panel on the right, about where a hand
	/// rests. Meters from the space's origin on the floor.
	private static let place: SIMD3<Float> = [-0.35, 0.8, -0.6]

	init() {
		root.name = "CinemaModelStand"
		root.position = Self.place
		// Turned to face the seat.
		root.orientation = simd_quatf(angle: atan2(-Self.place.x, -Self.place.z), axis: [0, 1, 0])
		root.addChild(grabber)
		// The bar sits just in front of and below the stand.
		grabber.position = [0, -0.02, 0.07]
		shelf.position = [0, 0.02, -0.07]
		grabber.addChild(shelf)
		grabber.isEnabled = false
	}

	/// Shows the model `request` names, in place of any other, or takes the stand away for nil.
	func show(_ request: CinemaModelRequest?, environment: CinemaEnvironment) async {
		clear()
		guard let request else {
			grabber.isEnabled = false
			return
		}
		// The bar and the readings show while the model loads, and if it won't, so it can be put away.
		grabber.isEnabled = true
		guard let url = await DeviceModelSource.shared.localURL(for: request.modelName) else {
			Logger.services.error("🎬 [Cinema] No model \(request.modelName, privacy: .public) for the stand")
			return
		}
		let model: Entity
		do {
			model = try await Entity(contentsOf: url)
		} catch {
			Logger.services.error("🎬 [Cinema] Model \(request.modelName, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
			return
		}
		guard !Task.isCancelled else { return }
		ShowcaseDisplays.matte(model)
		let holder = Entity()
		holder.name = "stand-\(request.modelName)"
		standHeight = ShowcaseDisplays.stand(model, in: holder)
		model.components.set(Self.accessibility(for: request))
		if light == nil {
			light = await Self.light(for: environment)
		}
		guard !Task.isCancelled else { return }
		if let light {
			shelf.addChild(light)
			Self.receive(light, in: holder)
		}
		shelf.addChild(holder)
		placeTag()
	}

	func clear() {
		shelf.children.removeAll()
		standHeight = 0
	}

	/// Hangs the readings beside the model, facing the seat like the stand. Nil takes down the
	/// card SwiftUI dropped; a new one replaces the old.
	func setTag(_ tag: Entity?) {
		if self.tag !== tag {
			self.tag?.removeFromParent()
			self.tag = tag
		}
		placeTag()
	}

	private func placeTag() {
		guard let tag else { return }
		if tag.parent !== grabber {
			grabber.addChild(tag)
		}
		let height = tag.visualBounds(relativeTo: tag).extents.y
		tag.position = shelf.position + [0.2, max(standHeight, 0.08) / 2 + height / 2, 0]
	}

	/// Names the model for VoiceOver, like a model on the showcase's tables.
	private static func accessibility(for request: CinemaModelRequest) -> AccessibilityComponent {
		var component = AccessibilityComponent()
		component.isAccessibilityElement = true
		component.traits = [.button]
		component.label = LocalizedStringResource(stringLiteral: request.deviceName)
		component.value = LocalizedStringResource("Pick up to turn it over", comment: "Cinema: VoiceOver hint for the device model on the stand in front of the seat")
		return component
	}

	/// A bar like a window's, the cinema panel's twin.
	private static func makeGrabber() -> Entity {
		var material = UnlitMaterial(color: .white)
		material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
		let bar = ModelEntity(mesh: .generateBox(width: 0.08, height: 0.008, depth: 0.008, cornerRadius: 0.004), materials: [material])
		bar.name = "StandGrabber"
		ManipulationComponent.configureEntity(
			bar,
			hoverEffect: .highlight(.default),
			allowedInputTypes: .all,
			collisionShapes: [.generateBox(width: 0.14, height: 0.035, depth: 0.03)]
		)
		var manipulation = bar.components[ManipulationComponent.self] ?? ManipulationComponent()
		manipulation.releaseBehavior = .stay
		manipulation.dynamics.scalingBehavior = .none
		manipulation.dynamics.primaryRotationBehavior = .none
		manipulation.dynamics.secondaryRotationBehavior = .none
		bar.components.set(manipulation)
		var accessibility = AccessibilityComponent()
		accessibility.isAccessibilityElement = true
		accessibility.label = LocalizedStringResource("Move the model stand", comment: "Cinema: VoiceOver label for the bar under the device model's stand that moves it")
		bar.components.set(accessibility)
		return bar
	}

	/// Light from the environment's own image, so the model is lit like the tent around it.
	private static func light(for environment: CinemaEnvironment) async -> Entity? {
		guard let url = cinemaEnvironmentImageURL(named: environment.imageName),
			  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
			  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
				  kCGImageSourceCreateThumbnailFromImageAlways: true,
				  kCGImageSourceThumbnailMaxPixelSize: 1024
			  ] as CFDictionary) else { return nil }
		do {
			let resource = try await EnvironmentResource(equirectangular: image, withName: "CinemaStand-\(environment.rawValue)")
			let light = Entity()
			light.name = "CinemaStandLight"
			light.components.set(ImageBasedLightComponent(source: .single(resource), intensityExponent: 1))
			return light
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make the stand's light: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	private static func receive(_ light: Entity, in entity: Entity) {
		var pending = [entity]
		while let next = pending.popLast() {
			if next.components.has(ModelComponent.self) {
				next.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
			}
			pending += next.children
		}
	}
}
#endif
