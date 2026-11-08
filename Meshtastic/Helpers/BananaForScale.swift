//
//  BananaForScale.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/26.
//
import OSLog
import RealityKit

/// A banana at its real size, about 18.5 cm tip to stem, beside a device model for scale: standing
/// on the Vision Pro cinema's stand, or on the table in the iPhone and iPad AR view. The model
/// is built from a public domain drawing by `scripts/cinema/banana_for_scale.py`, standing on its
/// tip with the drawing's front facing +z.
@available(iOS 18.0, macCatalyst 18.0, visionOS 2.0, *)
enum BananaForScale {
	/// The banana as built, standing on its tip. Nil if the model won't load.
	@MainActor
	static func load() async -> Entity? {
		guard let url = Bundle.main.url(forResource: "banana_for_scale", withExtension: "usdz") else {
			Logger.services.error("The banana for scale isn't in the app")
			return nil
		}
		let banana: Entity
		do {
			banana = try await Entity(contentsOf: url)
		} catch {
			Logger.services.error("Couldn't load the banana for scale: \(error.localizedDescription, privacy: .public)")
			return nil
		}
		var accessibility = AccessibilityComponent()
		accessibility.isAccessibilityElement = true
		accessibility.label = LocalizedStringResource("Banana for scale", comment: "Cinema: VoiceOver label for the banana beside the device model on the stand")
		banana.components.set(accessibility)
		return banana
	}

	/// The banana standing on its tip with the stem up, as on the cinema's stand, on y = 0 with its
	/// side toward the model at x = 0 and the rest of it toward -x. Nil if the model won't load.
	@MainActor
	static func standing() async -> Entity? {
		guard let banana = await load() else { return nil }
		let standing = Entity()
		standing.addChild(banana)
		let bounds = banana.visualBounds(relativeTo: standing)
		banana.position = [-bounds.max.x, -bounds.min.y, -bounds.center.z]
		return standing
	}

	#if os(visionOS)
	/// The banana on a clear plate like the model's, standing on its tip with the stem up, its
	/// side toward the model at x = 0. Nil if the model won't load.
	@MainActor
	static func make(plateThickness: Float, plateMaterial: some Material) async -> Entity? {
		guard let banana = await load() else { return nil }
		let bounds = banana.visualBounds(relativeTo: nil)
		banana.position = [-bounds.max.x, plateThickness - bounds.min.y, -bounds.center.z]

		let plate = Entity()
		plate.name = "BananaPlate"
		let width = bounds.extents.x
		let base = ModelEntity(
			mesh: .generateBox(width: width + 0.02, height: plateThickness, depth: bounds.extents.z + 0.03, cornerRadius: 0.002),
			materials: [plateMaterial]
		)
		base.position = [-width / 2, plateThickness / 2, 0]
		plate.addChild(base)
		plate.addChild(banana)
		return plate
	}
	#endif
}
