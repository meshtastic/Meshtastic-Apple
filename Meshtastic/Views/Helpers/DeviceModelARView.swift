//
//  DeviceModelARView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftData
import SwiftUI
import RealityKit

/// A radio's model in the room at its real size, standing on a table or the floor. A card over the
/// camera view has the node's live readings and a button that lays a banana beside the model for
/// scale. The connected radio's model shows its live screen, with the radio's buttons under the
/// camera view. Quick Look can place a model too, but can't change its texture or add to it.
@available(iOS 18.0, *)
struct DeviceModelARView: View {
	let request: DeviceModelFullScreenRequest
	/// The radio is connected with its screen to show. Only the connected radio's model gets it.
	let liveScreen: Bool

	@Environment(\.dismiss) private var dismiss
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.modelContext) private var context
	/// A scene can only hold an entity once, so this view stands its own copy.
	@State private var stage: DeviceModelStage
	/// Whether a surface has been found for the model to stand on.
	@State private var placed = false
	@State private var reading: CinemaNodeReading?
	/// A banana lies beside the model.
	@State private var showsBanana = false
	/// The banana, loaded the first time it's shown.
	@State private var banana: Entity?
	/// How far the model reaches from its middle however it's turned, so the banana lies clear of it.
	private let reach: Float

	private var accessoryManager: AccessoryManager { AccessoryManager.shared }
	private static let anchorName = "DeviceModelARAnchor"

	init(request: DeviceModelFullScreenRequest, liveScreen: Bool) {
		self.request = request
		self.liveScreen = liveScreen
		_stage = State(initialValue: DeviceModelStage(model: request.model.clone(recursive: true), facingFront: true))
		let extents = request.model.visualBounds(relativeTo: nil).extents
		reach = simd_length(SIMD2(extents.x, extents.z)) / 2
	}

	/// The radio's live screen on the model and its buttons under the camera view.
	private var showsLiveScreen: Bool {
		liveScreen && !request.isChirpy && stage.hasScreen
	}

	var body: some View {
		ZStack {
			RealityView { content in
				content.camera = .spatialTracking
				// Any horizontal surface; the model stands on it at its own size.
				let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.1, 0.1]))
				anchor.name = Self.anchorName
				anchor.addChild(stage.makeStandingScene())
				content.add(anchor)
				let placed = $placed
				stage.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak stage] event in
					stage?.advance(by: Float(event.deltaTime))
					if anchor.isAnchored, !placed.wrappedValue {
						placed.wrappedValue = true
					}
				}
			} update: { content in
				stage.screenSource = showsLiveScreen ? accessoryManager.displayMirror : nil
				guard let anchor = content.entities.first(where: { $0.name == Self.anchorName }) else { return }
				if showsBanana, let banana {
					if banana.parent == nil {
						// On the model's left, as on the cinema's stand, a little clear of it.
						banana.position = [-(reach + 0.03), 0, 0]
						anchor.addChild(banana)
					}
				} else {
					banana?.removeFromParent()
				}
			}
			.ignoresSafeArea()
			.gesture(turnGesture)
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(String(
				localized: "3D model of \(request.name) in your space",
				comment: "Accessibility label for the camera view showing a radio's 3D model in the room; the argument is the device name"
			))

			VStack(spacing: 16) {
				card
				Spacer()
				if !placed {
					Text("Point the camera at a table or the floor.", comment: "Hint in the camera view while it looks for a surface to stand the radio's 3D model on")
						.font(.callout)
						.padding(12)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				if showsLiveScreen {
					DeviceRemoteControl { event in
						Task { await accessoryManager.sendDisplayInput(event) }
					}
					.padding(16)
					.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
				}
			}
			.padding()
		}
		// Its own claim on the stream, while the app is in front: the model view behind this cover
		// may go off screen.
		.task(id: showsLiveScreen && scenePhase == .active) {
			if showsLiveScreen, scenePhase == .active {
				accessoryManager.startDisplayMirror(for: .deviceModelAR)
			} else {
				accessoryManager.stopDisplayMirror(for: .deviceModelAR)
			}
		}
		.onDisappear { accessoryManager.stopDisplayMirror(for: .deviceModelAR) }
		.task(id: request.nodeNum) {
			guard let nodeNum = request.nodeNum else {
				reading = nil
				return
			}
			while !Task.isCancelled {
				reading = CinemaNodeReading(nodeNum: nodeNum, context: context)
				try? await Task.sleep(for: .seconds(CinemaNodeReading.refresh))
			}
		}
		.task(id: showsBanana) {
			if showsBanana, banana == nil {
				banana = await BananaForScale.lyingDown()
			}
		}
	}

	/// The node's name and readings, the banana button, and the close button, like the card beside
	/// a model on the Vision Pro cinema's stand.
	private var card: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .top, spacing: 10) {
				if let reading {
					CircleText(text: reading.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: reading.num))), circleSize: 40)
				}
				VStack(alignment: .leading, spacing: 2) {
					Text(reading?.longName ?? request.name)
						.font(.headline)
					if reading != nil {
						Text(request.name)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
				Spacer(minLength: 8)
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
			if let reading {
				CinemaNodeReadings(reading: reading)
			}
			Toggle(isOn: $showsBanana) {
				Label {
					Text("Banana for Scale", comment: "Cinema: button on the card beside a device model on the stand; lays a real-size banana beside it")
				} icon: {
					// Stem up, like the banana on the cinema's stand.
					Image("custom.banana")
						.rotationEffect(.degrees(-90))
				}
			}
			.toggleStyle(.button)
		}
		.padding(16)
		.frame(maxWidth: 420, alignment: .leading)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
