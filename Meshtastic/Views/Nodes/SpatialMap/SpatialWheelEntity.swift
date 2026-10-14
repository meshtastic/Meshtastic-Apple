//
//  SpatialWheelEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
#if os(visionOS)
import RealityKit
import UIKit

/// Marks the bezel and handles, so a tap on them doesn't clear the selection.
struct SpatialWheelComponent: Component {}

/// The compass bezel around the disk's rim, with N E S W on top, and eight handles sticking out
/// like a ship's wheel. It sits in the rotating model, so north on the bezel stays with the map.
/// Its own sizes are in meters: the entity is counter-scaled against the model's scale.
@MainActor
final class SpatialWheelEntity {
	let root = Entity()

	private struct Shape: Equatable {
		let diskRadius: Float
		let bottom: Float
		let top: Float
	}

	private var shape: Shape?
	private let bezel = ModelEntity()
	private let marks = Entity()
	private var handles: [Entity] = []

	private static let bezelMaterial: PhysicallyBasedMaterial = {
		var material = PhysicallyBasedMaterial()
		material.baseColor = .init(tint: UIColor(white: 0.6, alpha: 1))
		material.metallic = 0.7
		material.roughness = 0.35
		return material
	}()

	private static let knobMaterial: PhysicallyBasedMaterial = {
		var material = PhysicallyBasedMaterial()
		material.baseColor = .init(tint: UIColor(white: 0.78, alpha: 1))
		material.metallic = 0.5
		material.roughness = 0.3
		return material
	}()

	init() {
		SpatialWheelComponent.registerComponent()
		root.name = "wheel"
		bezel.name = "bezel"
		root.addChild(bezel)
		root.addChild(marks)
		addMarks()
		for _ in 0..<SpatialWheelLayout.handleCount {
			let handle = makeHandle()
			handles.append(handle)
			root.addChild(handle)
		}
		for entity in [bezel] + handles {
			entity.components.set(InputTargetComponent())
			entity.components.set(HoverEffectComponent())
			entity.components.set(SpatialWheelComponent())
		}
	}

	/// Builds the wheel for a disk of a radius, with the bezel from `bottom` up to `top`, all in
	/// meters. Does nothing when they haven't changed by more than a millimeter.
	func update(diskRadius: Float, bottom: Float, top: Float) {
		let new = Shape(diskRadius: diskRadius, bottom: bottom, top: top)
		if let shape, abs(shape.diskRadius - new.diskRadius) < 0.001, abs(shape.bottom - new.bottom) < 0.001, abs(shape.top - new.top) < 0.001 {
			return
		}
		shape = new
		let inner = diskRadius + SpatialWheelLayout.gap
		let width = SpatialWheelLayout.bezelWidth
		let geometry = SpatialBezelMesh(innerRadius: inner, width: width, bottom: bottom, top: top, chamfer: SpatialWheelLayout.chamfer)
		var descriptor = MeshDescriptor(name: "bezel")
		descriptor.positions = MeshBuffer(geometry.positions)
		descriptor.normals = MeshBuffer(geometry.normals)
		descriptor.primitives = .triangles(geometry.indices)
		if let mesh = try? MeshResource.generate(from: [descriptor]) {
			bezel.model = ModelComponent(mesh: mesh, materials: [Self.bezelMaterial])
		}
		bezel.components.set(CollisionComponent.inputTarget(Self.ringShapes(inner: inner, width: width, bottom: bottom, top: top)))

		// Letters lie on the bezel's top, their tops toward the center so they read from outside.
		let middle = inner + width / 2
		for (mark, point) in zip(marks.children, SpatialWheelLayout.compassPoints) {
			let p = SpatialWheelLayout.point(distance: middle, angle: point.angle)
			mark.position = [p.x, top + 0.0005, p.y]
		}

		let knobY = max(top - SpatialWheelLayout.knobRadius - 0.002, bottom + SpatialWheelLayout.knobRadius)
		let spokeStart = inner + width - 0.002
		for (handle, angle) in zip(handles, SpatialWheelLayout.handleAngles) {
			let p = SpatialWheelLayout.point(distance: spokeStart, angle: angle)
			handle.position = [p.x, knobY, p.y]
			handle.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
		}
	}

	/// The four letters, each laid flat and turned so its top points at the center. N is red.
	private func addMarks() {
		for point in SpatialWheelLayout.compassPoints {
			let isNorth = point.letter == "N"
			let mesh = MeshResource.generateText(
				point.letter,
				extrusionDepth: 0.0008,
				font: .systemFont(ofSize: isNorth ? 0.017 : 0.014, weight: .heavy),
				containerFrame: .zero,
				alignment: .center,
				lineBreakMode: .byClipping
			)
			let letter = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: isNorth ? .systemRed : .white)])
			// Center the glyph on its own origin, then lay it face up with its top toward -z.
			let center = mesh.bounds.center
			letter.position = [-center.x, 0, center.y]
			letter.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
			let holder = Entity()
			holder.name = "mark-\(point.letter)"
			holder.addChild(letter)
			// At angle a the center is in direction a + π; turn the letter's top (-z) to face it.
			holder.orientation = simd_quatf(angle: point.angle + .pi / 2, axis: [0, 1, 0])
			marks.addChild(holder)
		}
	}

	/// A handle along +x from its own origin: a short spoke and a round knob on the end.
	private func makeHandle() -> Entity {
		let length = SpatialWheelLayout.spokeLength + 0.002
		let radius = SpatialWheelLayout.knobRadius
		let handle = Entity()
		handle.name = "handle"
		let spoke = ModelEntity(mesh: .generateCylinder(height: length, radius: SpatialWheelLayout.spokeRadius), materials: [Self.bezelMaterial])
		spoke.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
		spoke.position = [length / 2, 0, 0]
		let knob = ModelEntity(mesh: .generateSphere(radius: radius), materials: [Self.knobMaterial])
		knob.position = [length, 0, 0]
		handle.addChild(spoke)
		handle.addChild(knob)
		// A target a little bigger than the knob, and the spoke, so the handle is easy to catch.
		let knobShape = ShapeResource.generateSphere(radius: radius * 1.4).offsetBy(translation: [length, 0, 0])
		let spokeShape = ShapeResource.generateCapsule(height: length, radius: radius * 0.7)
			.offsetBy(rotation: simd_quatf(angle: -.pi / 2, axis: [0, 0, 1]), translation: [length / 2, 0, 0])
		handle.components.set(CollisionComponent.inputTarget([knobShape, spokeShape]))
		return handle
	}

	/// Boxes around the ring, since a collision shape can't be a ring.
	private static func ringShapes(inner: Float, width: Float, bottom: Float, top: Float, count: Int = 48) -> [ShapeResource] {
		let middle = inner + width / 2
		let height = max(top - bottom, 0.004)
		let chord = 2 * (inner + width) * sin(.pi / Float(count)) * 1.05
		return (0..<count).map { i in
			let angle = Float(i) / Float(count) * 2 * .pi
			let p = SpatialWheelLayout.point(distance: middle, angle: angle)
			return ShapeResource.generateBox(width: width, height: height, depth: chord)
				.offsetBy(rotation: simd_quatf(angle: angle, axis: [0, 1, 0]), translation: [p.x, (top + bottom) / 2, p.y])
		}
	}
}
#endif
