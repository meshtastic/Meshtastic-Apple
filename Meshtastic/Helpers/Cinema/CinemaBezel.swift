//
//  CinemaBezel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
#if os(visionOS)
import RealityKit
import SwiftUI
import UIKit

/// A bezel like an older iPad's around a panel: a black border whose inner corners follow the
/// panel's rounded corners, and a thin rim in the spatial map wheel's brushed metal. Both sit
/// behind the panel's face, so they never cover its content.
enum CinemaBezel {
	static let name = "Bezel"

	/// Adds the bezel to `panel`, or replaces it. `pointWidth` and `cornerRadius` are the panel's
	/// width and corner radius in points, to match its corners in the panel's own units.
	static func add(to panel: Entity, pointWidth: CGFloat, cornerRadius: CGFloat) {
		remove(from: panel)
		let size = panel.visualBounds(relativeTo: panel).extents
		guard size.x > 0, size.y > 0 else { return }
		let width = CGFloat(size.x), height = CGFloat(size.y)
		let radius = cornerRadius * width / pointWidth
		let border = width * 0.0225
		let rim = width * 0.045 * 0.22

		var black = PhysicallyBasedMaterial()
		black.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1))
		black.roughness = 0.25
		var metal = PhysicallyBasedMaterial()
		metal.baseColor = .init(tint: UIColor(white: 0.6, alpha: 1))
		metal.metallic = 0.7
		metal.roughness = 0.35

		let bezel = Entity()
		bezel.name = name
		if let ring = ring(around: CGSize(width: width, height: height), radius: radius, thickness: border, depth: Float(border * 0.7), material: black) {
			bezel.addChild(ring)
		}
		if let ring = ring(around: CGSize(width: width + border * 2, height: height + border * 2), radius: radius + border, thickness: rim, depth: Float(border), material: metal) {
			bezel.addChild(ring)
		}
		panel.addChild(bezel)
	}

	/// Takes the bezel off, so the panel can be measured on its own.
	static func remove(from panel: Entity) {
		panel.findEntity(named: name)?.removeFromParent()
	}

	/// A flat rounded-rectangle ring `thickness` wide around a `hole` with `radius` corners, its
	/// front face just behind the panel's face.
	private static func ring(around hole: CGSize, radius: CGFloat, thickness: CGFloat, depth: Float, material: PhysicallyBasedMaterial) -> ModelEntity? {
		let width = hole.width, height = hole.height
		var path = Path()
		path.addRoundedRect(
			in: CGRect(x: -width / 2 - thickness, y: -height / 2 - thickness, width: width + thickness * 2, height: height + thickness * 2),
			cornerSize: CGSize(width: radius + thickness, height: radius + thickness),
			style: .continuous
		)
		path.addRoundedRect(
			in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
			cornerSize: CGSize(width: radius, height: radius),
			style: .continuous
		)
		var options = MeshResource.ShapeExtrusionOptions()
		options.extrusionMethod = .linear(depth: depth)
		options.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: 12)
		guard let mesh = try? MeshResource(extruding: path.normalized(eoFill: true), extrusionOptions: options) else { return nil }
		let entity = ModelEntity(mesh: mesh, materials: [material])
		let bounds = entity.visualBounds(relativeTo: entity)
		entity.position.z = -bounds.max.z - Float(thickness) * 0.02
		return entity
	}
}
#endif
