//
//  DeviceModelScreen.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//

import CoreGraphics
import Metal
import OSLog
import RealityKit

/// The radio's live screen on a device model's display: a plane just in front of the model's
/// `Screen` part, textured with each new picture. The picture keeps its own shape inside the
/// display, turned a quarter if the display is mounted the other way round, with no lighting so it
/// reads like a lit screen. Shared by the model views and the stand in the Vision Pro cinema.
@available(iOS 18.0, macCatalyst 18.0, visionOS 1.0, *)
@MainActor
final class DeviceModelScreen {
	/// The front of the model's `Screen` part, in the model's own space.
	let bounds: BoundingBox
	private let plane = ModelEntity()
	private var texture: TextureResource?
	private var shape: Shape?
	/// The picture on the display, recorded once its texture is made.
	private var lastImage: CGImage?
	/// A picture whose texture failed, skipped until the source supplies another so the error
	/// isn't retried and logged every frame.
	private var failedImage: CGImage?

	/// Where a model's display is, when it has a part named Screen with something in it.
	static func bounds(of model: Entity) -> BoundingBox? {
		guard let screen = model.findEntity(named: "Screen") else { return nil }
		let box = screen.visualBounds(relativeTo: model)
		return box.isEmpty ? nil : box
	}

	/// Puts the screen on `model`, whose display is at `bounds`, hidden until a picture comes.
	init(bounds: BoundingBox, on model: Entity) {
		self.bounds = bounds
		plane.isEnabled = false
		model.addChild(plane)
	}

	/// Nil when the model has no display to draw on.
	convenience init?(on model: Entity) {
		guard let bounds = Self.bounds(of: model) else { return nil }
		self.init(bounds: bounds, on: model)
	}

	struct Shape: Equatable {
		let width: Float
		let height: Float
		let turned: Bool
	}

	/// The picture's size on a display `slotWidth` by `slotHeight`: its own shape, as large as fits,
	/// turned a quarter when the display is mounted the other way round.
	nonisolated static func shape(imageWidth: Int, imageHeight: Int, slotWidth: Float, slotHeight: Float) -> Shape {
		let aspect = Float(imageWidth) / Float(max(imageHeight, 1))
		let turned = (aspect > 1.05 && slotHeight > slotWidth * 1.05) || (aspect < 0.95 && slotWidth > slotHeight * 1.05)
		// The picture's width runs along the display's height when it's turned.
		let along = turned ? slotHeight : slotWidth
		let across = turned ? slotWidth : slotHeight
		let width = min(along, across * aspect)
		return Shape(width: width, height: width / aspect, turned: turned)
	}

	/// Draws the picture on the display, or hides the screen for nil. Cheap when the picture is the
	/// one already showing, so it can be called every frame.
	func show(_ image: CGImage?) {
		guard let image else {
			plane.isEnabled = false
			lastImage = nil
			failedImage = nil
			return
		}
		guard image !== lastImage, image !== failedImage else { return }
		let shape = Self.shape(
			imageWidth: image.width,
			imageHeight: image.height,
			slotWidth: bounds.extents.x,
			slotHeight: bounds.extents.y
		)

		do {
			if let texture {
				try texture.replace(withImage: image, options: .init(semantic: .color))
			} else {
				let texture = try TextureResource(image: image, options: .init(semantic: .color))
				self.texture = texture
				var material = UnlitMaterial()
				material.color = .init(tint: .white, texture: .init(texture, sampler: Self.nearestSampler))
				plane.model = ModelComponent(mesh: .generatePlane(width: 1, height: 1), materials: [material])
			}
		} catch {
			failedImage = image
			Logger.services.error("Device model screen: couldn't make a texture: \(error.localizedDescription, privacy: .public)")
			return
		}
		lastImage = image
		failedImage = nil
		if shape != self.shape {
			self.shape = shape
			plane.scale = [shape.width, shape.height, 1]
			plane.orientation = shape.turned ? simd_quatf(angle: .pi / 2, axis: [0, 0, 1]) : simd_quatf()
			// Just in front of the display's face, so the case around it can't cover it.
			let center = bounds.center
			plane.position = [center.x, center.y, bounds.max.z + 0.00005]
		}
		plane.isEnabled = true
	}

	/// Each radio pixel stays a crisp square, however close the viewer gets.
	private static let nearestSampler: MaterialParameters.Texture.Sampler = {
		let descriptor = MTLSamplerDescriptor()
		descriptor.minFilter = .nearest
		descriptor.magFilter = .nearest
		descriptor.mipFilter = .notMipmapped
		return MaterialParameters.Texture.Sampler(descriptor)
	}()
}
