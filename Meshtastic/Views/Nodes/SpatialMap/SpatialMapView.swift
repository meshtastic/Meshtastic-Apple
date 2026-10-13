//
//  SpatialMapView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import RealityKit
import SwiftUI

/// The RealityView in the volume: hands the model's state to the scene controller, keeps the map
/// fitted to the volume as it is resized, and turns taps and drags into selection and rotation.
struct SpatialMapView: View {
	let model: SpatialMapModel
	let scene: SpatialSceneController
	let traffic: SpatialTrafficController
	let preset: ModemPresets
	let showLinks: Bool
	let onOpenNode: (Int64) -> Void

	@State private var yaw: Float = 0
	@State private var wheelDrag: SpatialWheelDrag?
	/// The volume's size, so a resize runs the update closure and refits the map.
	@State private var volumeSize: Size3D = .zero

	var body: some View {
		GeometryReader3D { proxy in
			RealityView { content, _ in
				scene.fit(volume: content.convert(proxy.frame(in: .local), from: .local, to: .scene))
				content.add(scene.root)
				scene.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
					traffic.step(deltaTime: event.deltaTime)
				}
			} update: { content, attachments in
				_ = volumeSize
				scene.fit(volume: content.convert(proxy.frame(in: .local), from: .local, to: .scene))
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
							SpatialNodeLabel(node: node, isSelected: num == model.selectedNodeNum) {
								model.select(num)
							}
						}
					}
				}
				if let selected = model.selectedNodeNum, let node = model.nodesByNum[selected] {
					Attachment(id: "detail") {
						SpatialNodeDetailPanel(node: node, preset: preset) {
							onOpenNode(node.id)
						} onCenter: {
							turnToFront(node.id)
						} onClose: {
							model.select(nil)
						}
					}
				}
			}
			.gesture(tap)
			.gesture(doubleTap)
			.gesture(drag)
			.onChange(of: proxy.size, initial: true) { _, size in
				volumeSize = size
			}
		}
		.onChange(of: model.placement?.revision) {
			reset(animated: false)
		}
	}

	private var tap: some Gesture {
		SpatialTapGesture()
			.targetedToAnyEntity()
			.onEnded { value in
				// The bezel and handles are for turning; a tap on them keeps the selection.
				guard !Self.isWheel(value.entity) else { return }
				let point = value.convert(value.location3D, from: .local, to: .scene)
				model.select(Self.nodeNum(of: value.entity) ?? scene.nearestPin(toScenePoint: point))
			}
	}

	private var doubleTap: some Gesture {
		SpatialTapGesture(count: 2)
			.targetedToAnyEntity()
			.onEnded { value in
				if Self.nodeNum(of: value.entity) == nil { reset(animated: true) }
			}
	}

	/// Dragging the map, the bezel or a handle turns the map, following the hand around the middle
	/// like a wheel.
	private var drag: some Gesture {
		DragGesture()
			.targetedToAnyEntity()
			.onChanged { value in
				let point = scene.tablePoint(value.convert(value.location3D, from: .local, to: .scene))
				if var drag = wheelDrag {
					yaw = drag.update(x: point.x, z: point.y)
					wheelDrag = drag
				} else {
					let start = scene.tablePoint(value.convert(value.startLocation3D, from: .local, to: .scene))
					var drag = SpatialWheelDrag(startYaw: yaw, x: start.x, z: start.y)
					yaw = drag.update(x: point.x, z: point.y)
					wheelDrag = drag
				}
				scene.setYaw(yaw)
			}
			.onEnded { _ in
				wheelDrag = nil
			}
	}

	/// Turns the map the short way round so a node faces the viewer.
	private func turnToFront(_ nodeNum: Int64) {
		guard let position = scene.pinPosition(nodeNum),
			  let target = SpatialVolumeFit.yawBringingToFront(x: position.x, z: position.z, from: yaw) else { return }
		yaw = target
		scene.setYaw(yaw, animated: true)
	}

	private func reset(animated: Bool) {
		yaw = 0
		scene.setYaw(0, animated: animated)
	}

	private static func isWheel(_ entity: Entity) -> Bool {
		var current: Entity? = entity
		while let entity = current {
			if entity.components.has(SpatialWheelComponent.self) { return true }
			current = entity.parent
		}
		return false
	}

	private static func nodeNum(of entity: Entity) -> Int64? {
		var current: Entity? = entity
		while let entity = current {
			if let pin = entity.components[NodePinComponent.self] { return pin.nodeNum }
			current = entity.parent
		}
		return nil
	}
}

struct SpatialNodeLabel: View {
	let node: SpatialNodeSnapshot
	let isSelected: Bool
	let onSelect: () -> Void

	/// The label is a button too, since it is a bigger thing to look at than the pin.
	var body: some View {
		Button(action: onSelect) {
			Text(node.shortName)
				.font(.caption2.bold())
				.padding(.horizontal, 7)
				.padding(.vertical, 3)
		}
		.buttonStyle(.plain)
		.contentShape(.hoverEffect, .capsule)
		.hoverEffect(.highlight)
		.glassBackgroundEffect(in: .capsule)
		.opacity(node.isOnline || isSelected ? 1 : 0.65)
	}
}
#endif
