//
//  SpatialMapView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import RealityKit
import SwiftUI

/// The RealityView in the volume: hands the model's state to the scene controller and turns
/// taps, drags and pinches into selection, rotation, sliding (on the grab handle) and zoom.
struct SpatialMapView: View {
	let model: SpatialMapModel
	let scene: SpatialSceneController
	let traffic: SpatialTrafficController
	let preset: ModemPresets
	let showLinks: Bool
	let onOpenNode: (Int64) -> Void

	@State private var yaw: Float = 0
	@State private var startYaw: Float?
	@State private var zoom: Float = 1
	@State private var startZoom: Float?
	@State private var pan: SIMD2<Float> = .zero
	@State private var startPan: SIMD2<Float>?

	/// Points per meter in a volume, for turning a drag into a rotation.
	private static let pointsPerMeter: Double = 1360

	var body: some View {
		GeometryReader3D { proxy in
			RealityView { content, _ in
				let bounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
				scene.install(floorY: bounds.min.y)
				content.add(scene.root)
				scene.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
					traffic.step(deltaTime: event.deltaTime)
				}
			} update: { _, attachments in
				scene.apply(placement: model.placement)
				scene.apply(terrainEntity: model.terrainEntity, building: model.isBuildingTerrain)
				scene.apply(nodes: model.nodes)
				traffic.applyBaseGlow()
				scene.apply(links: showLinks ? model.links : [], preset: preset)
				scene.apply(labels: model.labeledNodeNums, attachments: attachments)
				scene.apply(selection: model.selectedNodeNum, attachments: attachments)
			} attachments: {
				ForEach(model.labeledNodeNums, id: \.self) { num in
					Attachment(id: num) {
						if let node = model.nodesByNum[num] {
							SpatialNodeLabel(node: node, isSelected: num == model.selectedNodeNum)
						}
					}
				}
				if let selected = model.selectedNodeNum, let node = model.nodesByNum[selected] {
					Attachment(id: "detail") {
						SpatialNodeDetailPanel(node: node, preset: preset) {
							onOpenNode(node.id)
						} onCenter: {
							center(on: node.id)
						} onClose: {
							model.select(nil)
						}
					}
				}
			}
			.gesture(tap)
			.gesture(doubleTap)
			.gesture(drag)
			.simultaneousGesture(magnify)
		}
		.onChange(of: model.placement?.revision) {
			reset(animated: false)
		}
	}

	private var tap: some Gesture {
		SpatialTapGesture()
			.targetedToAnyEntity()
			.onEnded { value in
				guard !Self.isGrabHandle(value.entity) else { return }
				model.select(Self.nodeNum(of: value.entity))
			}
	}

	private var doubleTap: some Gesture {
		SpatialTapGesture(count: 2)
			.targetedToAnyEntity()
			.onEnded { value in
				guard !Self.isGrabHandle(value.entity) else { return }
				if Self.nodeNum(of: value.entity) == nil { reset(animated: true) }
			}
	}

	/// On the grab handle a drag slides the map; anywhere else it turns the map.
	private var drag: some Gesture {
		DragGesture()
			.targetedToAnyEntity()
			.onChanged { value in
				if Self.isGrabHandle(value.entity) {
					let start = startPan ?? pan
					startPan = start
					let delta = value.convert(value.translation3D, from: .local, to: .scene)
					pan = Self.clampPan(start + SIMD2(delta.x, delta.z), zoom: zoom)
				} else {
					let start = startYaw ?? yaw
					startYaw = start
					// A drag across the volume's width is one full turn.
					yaw = start + Float(value.translation3D.x / Self.pointsPerMeter) * 2 * .pi
				}
				scene.setTransform(yaw: yaw, scale: zoom, pan: pan)
			}
			.onEnded { _ in
				startYaw = nil
				startPan = nil
			}
	}

	private var magnify: some Gesture {
		MagnifyGesture()
			.targetedToAnyEntity()
			.onChanged { value in
				let start = startZoom ?? zoom
				startZoom = start
				zoom = min(max(start * Float(value.magnification), 0.5), 2.5)
				pan = Self.clampPan(pan, zoom: zoom)
				scene.setTransform(yaw: yaw, scale: zoom, pan: pan)
			}
			.onEnded { _ in startZoom = nil }
	}

	/// Slides the map so a node sits under the volume's center, at the current zoom.
	private func center(on nodeNum: Int64) {
		guard let position = scene.pinPosition(nodeNum) else { return }
		let rotated = simd_quatf(angle: yaw, axis: [0, 1, 0]).act(position)
		pan = Self.clampPan(SIMD2(-rotated.x, -rotated.z) * zoom, zoom: zoom)
		scene.setTransform(yaw: yaw, scale: zoom, pan: pan, animated: true)
	}

	private func reset(animated: Bool) {
		yaw = 0
		zoom = 1
		pan = .zero
		scene.setTransform(yaw: 0, scale: 1, pan: .zero, animated: animated)
	}

	/// Keeps part of the round terrain inside the volume: the disk's center stays within a circle
	/// that grows with the zoom.
	private static func clampPan(_ pan: SIMD2<Float>, zoom: Float) -> SIMD2<Float> {
		let limit = max(zoom - 0.5, 0) * 0.5
		let length = simd_length(pan)
		return length > limit ? (limit > 0 ? pan * (limit / length) : .zero) : pan
	}

	private static func nodeNum(of entity: Entity) -> Int64? {
		var current: Entity? = entity
		while let entity = current {
			if let pin = entity.components[NodePinComponent.self] { return pin.nodeNum }
			current = entity.parent
		}
		return nil
	}

	private static func isGrabHandle(_ entity: Entity) -> Bool {
		var current: Entity? = entity
		while let entity = current {
			if entity.components.has(GrabHandleComponent.self) { return true }
			current = entity.parent
		}
		return false
	}
}

struct SpatialNodeLabel: View {
	let node: SpatialNodeSnapshot
	let isSelected: Bool

	var body: some View {
		Text(node.shortName)
			.font(.caption2.bold())
			.padding(.horizontal, 7)
			.padding(.vertical, 3)
			.glassBackgroundEffect(in: .capsule)
			.opacity(node.isOnline || isSelected ? 1 : 0.65)
	}
}
#endif
