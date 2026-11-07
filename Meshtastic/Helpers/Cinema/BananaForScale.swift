//
//  BananaForScale.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/26.
//
#if os(visionOS)
import CinemaContent
import OSLog
import RealityKit

/// A banana at its real size, about 18.5 cm tip to stem, to stand beside a device model for
/// scale. The model is built from a public domain drawing by `scripts/cinema/banana_for_scale.py`.
enum BananaForScale {
	/// The banana on a clear plate like the model's, standing on its tip with the stem up, its
	/// side toward the model at x = 0. Nil if the model won't load.
	@MainActor
	static func make(plateThickness: Float, plateMaterial: some Material) async -> Entity? {
		guard let url = cinemaPropURL(named: "banana_for_scale") else {
			Logger.services.error("🎬 [Cinema] The banana isn't in the app")
			return nil
		}
		let banana: Entity
		do {
			banana = try await Entity(contentsOf: url)
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't load the banana: \(error.localizedDescription, privacy: .public)")
			return nil
		}
		let bounds = banana.visualBounds(relativeTo: nil)
		banana.position = [-bounds.max.x, plateThickness - bounds.min.y, -bounds.center.z]
		var accessibility = AccessibilityComponent()
		accessibility.isAccessibilityElement = true
		accessibility.label = LocalizedStringResource("Banana for scale", comment: "Cinema: VoiceOver label for the banana beside the device model on the stand")
		banana.components.set(accessibility)

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
}
#endif
