//
//  DeviceModelARView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftUI
import RealityKit

/// The connected radio's model in the room at its real size, standing on a table or the floor,
/// with its live screen and the radio's buttons under the camera view. Quick Look can place a
/// model too, but can't change its texture, so the live screen needs a view of its own.
@available(iOS 18.0, *)
struct DeviceModelARView: View {
	let request: DeviceModelFullScreenRequest

	@Environment(\.dismiss) private var dismiss
	/// A scene can only hold an entity once, so this view stands its own copy.
	@State private var stage: DeviceModelStage
	/// Whether a surface has been found for the model to stand on.
	@State private var placed = false

	private var accessoryManager: AccessoryManager { AccessoryManager.shared }

	init(request: DeviceModelFullScreenRequest) {
		self.request = request
		_stage = State(initialValue: DeviceModelStage(model: request.model.clone(recursive: true), facingFront: true))
	}

	var body: some View {
		ZStack {
			RealityView { content in
				content.camera = .spatialTracking
				// Any horizontal surface; the model stands on it at its own size.
				let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.1, 0.1]))
				anchor.addChild(stage.makeStandingScene())
				content.add(anchor)
				stage.screenSource = accessoryManager.displayMirror
				let placed = $placed
				stage.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak stage] event in
					stage?.advance(by: Float(event.deltaTime))
					if anchor.isAnchored, !placed.wrappedValue {
						placed.wrappedValue = true
					}
				}
			} update: { _ in
				stage.screenSource = accessoryManager.displayMirror
			}
			.ignoresSafeArea()
			.gesture(turnGesture)
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(String(
				localized: "3D model of \(request.name) in your space",
				comment: "Accessibility label for the camera view showing a radio's 3D model in the room; the argument is the device name"
			))

			VStack(spacing: 16) {
				HStack {
					Spacer()
					Button {
						dismiss()
					} label: {
						Label("Close", systemImage: "xmark")
							.labelStyle(.iconOnly)
							.font(.body.weight(.semibold))
							.frame(width: 36, height: 36)
							.background(.ultraThinMaterial, in: Circle())
					}
					.buttonStyle(.plain)
				}
				Spacer()
				if !placed {
					Text("Point the camera at a table or the floor.", comment: "Hint in the camera view while it looks for a surface to stand the radio's 3D model on")
						.font(.callout)
						.padding(12)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				DeviceRemoteControl { event in
					Task { await accessoryManager.sendDisplayInput(event) }
				}
				.padding(16)
				.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
			}
			.padding()
		}
		// Its own claim on the stream: the model view behind this cover may go off screen.
		.task { accessoryManager.startDisplayMirror(for: .deviceModelAR) }
		.onDisappear { accessoryManager.stopDisplayMirror(for: .deviceModelAR) }
	}

	/// Sideways drags turn the model on its surface; it never tilts off it.
	private var turnGesture: some Gesture {
		DragGesture(minimumDistance: 8)
			.onChanged { value in
				if !stage.isDragging { stage.beginDrag() }
				stage.drag(by: value.translation)
			}
			.onEnded { _ in stage.endDrag() }
	}
}
#endif
