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
/// fitted to the volume as it is resized, and turns taps, drags and pinches into selection,
/// rotation and zoom.
struct SpatialMapView: View {
	let model: SpatialMapModel
	let scene: SpatialSceneController
	let traffic: SpatialTrafficController
	let preset: ModemPresets
	let onOpenNode: (Int64) -> Void
	let onCoverage: (Int64, SpatialCoverageAction) -> Void

	/// The zoom a pinch has reached, shown as a preview until its terrain is built.
	@State private var liveZoom: Double?
	@State private var pinchStartZoom: Double?
	@State private var pinchSettle: Task<Void, Never>?
	/// True while a drag or pinch is in progress. A cancelled gesture doesn't call onEnded but does
	/// reset these, so the next gesture never starts from a stale one.
	@GestureState private var isDragging = false
	@GestureState private var isPinching = false
	/// The volume's size, so a resize runs the update closure and refits the map.
	@State private var volumeSize: Size3D = .zero

	var body: some View {
		GeometryReader3D { proxy in
			RealityView { content, _ in
				scene.fit(volume: content.convert(proxy.frame(in: .local), from: .local, to: .scene))
				content.add(scene.root)
				scene.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
					traffic.step(deltaTime: event.deltaTime)
					scene.stepWheel(deltaTime: event.deltaTime)
					scene.stepBeacons(deltaTime: event.deltaTime)
					scene.route.step(deltaTime: event.deltaTime)
				}
			} update: { content, attachments in
				_ = volumeSize
				scene.fit(volume: content.convert(proxy.frame(in: .local), from: .local, to: .scene))
				scene.apply(placement: model.placement)
				scene.apply(terrainEntity: model.terrainEntity, building: model.isBuildingTerrain)
				scene.apply(weatherRadar: model.weatherRadarEntity, revision: model.weatherRadarRevision)
				scene.apply(coverage: model.coverageEntity, revision: model.coverageRevision, opacity: model.coverageOpacity)
				scene.apply(nodes: model.nodes)
				scene.apply(target: liveZoom.flatMap { model.circle(forZoom: $0) } ?? model.targetCircle)
				traffic.applyBaseGlow()
				// Hidden while a trace route is shown, as on the 2D map, so the two sets of colored
				// lines and pills can't be mixed up.
				scene.apply(links: shownLinks, pills: linkPills, preset: preset, attachments: attachments, attachmentIDs: linkPills.map { SpatialLinkDrawing.pillAttachmentID($0.id) })
				scene.apply(route: model.shownRoute, attachments: attachments, attachmentIDs: routeAttachmentIDs)
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
				ForEach(linkPills) { pill in
					Attachment(id: SpatialLinkDrawing.pillAttachmentID(pill.id)) {
						SpatialRouteSnrPill(snr: pill.snr, color: getSnrColor(snr: pill.snr, preset: preset))
							.opacity(pill.opacity)
					}
				}
				if let route = model.shownRoute {
					ForEach(route.layout.badges) { badge in
						Attachment(id: SpatialRouteDrawing.badgeAttachmentID(badge.id)) {
							SpatialRouteHopBadge(number: badge.number, isBack: badge.isBack)
						}
					}
					ForEach(route.layout.segments.filter { $0.snr != nil }) { segment in
						Attachment(id: SpatialRouteDrawing.pillAttachmentID(segment.id)) {
							SpatialRouteSnrPill(snr: segment.snr ?? 0, color: getSnrColor(snr: segment.snr ?? 0, preset: preset))
						}
					}
				}
				if let selected = model.selectedNodeNum, let node = model.nodesByNum[selected] {
					Attachment(id: "detail") {
						SpatialNodeDetailPanel(node: node, preset: preset, coverage: coverageState(node.id)) {
							onOpenNode(node.id)
						} onCenter: {
							model.zoomIn(on: node.id)
						} onCoverage: { action in
							onCoverage(node.id, action)
						} onClose: {
							model.select(nil)
						}
					}
				}
			}
			.gesture(tap)
			.gesture(doubleTap)
			.gesture(drag)
			.gesture(pinch)
			.onChange(of: proxy.size, initial: true) { _, size in
				volumeSize = size
			}
			.onChange(of: isDragging) { _, dragging in
				if !dragging { scene.endWheelDrag(at: nil) }
			}
			.onChange(of: isPinching) { _, pinching in
				if !pinching { endPinch() }
			}
		}
	}

	private var shownLinks: [SpatialLinkSnapshot] {
		model.shownRoute == nil ? model.links : []
	}

	/// Pills for the selected node's links, or for the newest links when nothing is selected.
	private var linkPills: [SpatialLinkPill] {
		SpatialLinkLayout.pills(for: shownLinks, selected: model.selectedNodeNum, connected: model.connectedNodeNum)
	}

	private var routeAttachmentIDs: [String] {
		guard let layout = model.shownRoute?.layout else { return [] }
		return layout.badges.map { SpatialRouteDrawing.badgeAttachmentID($0.id) }
			+ layout.segments.filter { $0.snr != nil }.map { SpatialRouteDrawing.pillAttachmentID($0.id) }
	}

	private var tap: some Gesture {
		SpatialTapGesture()
			.targetedToAnyEntity()
			.onEnded { value in
				scene.stopWheel()
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
				if Self.nodeNum(of: value.entity) == nil { reset() }
			}
	}

	/// Dragging the map, the bezel or a handle turns the map like a wheel. The scene controller keeps
	/// the turn, eases it each frame and lets a flick coast.
	private var drag: some Gesture {
		DragGesture()
			.targetedToAnyEntity()
			.updating($isDragging) { _, state, _ in state = true }
			.onChanged { value in
				scene.dragWheel(
					start: scene.tablePoint(value.convert(value.startLocation3D, from: .local, to: .scene)),
					current: scene.tablePoint(value.convert(value.location3D, from: .local, to: .scene)),
					time: value.gestureValue.time.timeIntervalSinceReferenceDate
				)
			}
			.onEnded { value in
				scene.endWheelDrag(at: value.gestureValue.time.timeIntervalSinceReferenceDate)
			}
	}

	/// Pinching zooms the geography: the table stays the same size and shows a smaller area around
	/// its center in more detail. The terrain is rebuilt when the pinch ends or pauses.
	private var pinch: some Gesture {
		MagnifyGesture()
			.targetedToAnyEntity()
			.updating($isPinching) { _, state, _ in state = true }
			.onChanged { value in
				let start = pinchStartZoom ?? model.zoom
				pinchStartZoom = start
				let zoom = model.clampedZoom(start * value.magnification)
				guard zoom != liveZoom else { return }
				liveZoom = zoom
				pinchSettle?.cancel()
				pinchSettle = Task {
					try? await Task.sleep(for: .milliseconds(500))
					guard !Task.isCancelled else { return }
					model.setZoom(zoom)
				}
			}
			.onEnded { _ in
				endPinch()
			}
	}

	/// Builds the zoom the pinch reached; also runs when the pinch is cancelled.
	private func endPinch() {
		pinchSettle?.cancel()
		pinchSettle = nil
		if let liveZoom { model.setZoom(liveZoom) }
		liveZoom = nil
		pinchStartZoom = nil
	}

	/// Shown only when the estimate is active and coverage isn't switched off.
	private func coverageState(_ nodeNum: Int64) -> SpatialCoverageCardState {
		guard let file = model.coverageByNode[nodeNum] else { return .none }
		return file.isActive && model.coverageMode != .off ? .shown(file.created) : .hidden(file.created)
	}

	/// Back to north at the back and the whole mesh.
	private func reset() {
		scene.resetYaw()
		model.resetZoom()
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
