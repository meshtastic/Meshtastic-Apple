//
//  DeviceModelARView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import ARKit
import AVFoundation
import Combine
import RealityKit
import ReplayKit
import SwiftUI

/// A radio's model at its real size, standing on a table or the floor and turned to face you, or on
/// its own in the Object view. Like Quick Look it can record the screen and share the model's file;
/// unlike Quick Look it can stand a banana beside the model for scale, and the connected radio's
/// model shows its live screen, with the radio's buttons under the camera view.
@available(iOS 18.0, *)
struct DeviceModelARView: View {
	let request: DeviceModelFullScreenRequest
	/// The radio is connected with its screen to show. Only the connected radio's model gets it.
	let liveScreen: Bool

	/// The camera view, or the model on its own.
	enum Mode: Hashable {
		case room
		case object
	}

	@Environment(\.dismiss) private var dismiss
	@Environment(\.scenePhase) private var scenePhase
	@State private var mode = Mode.room
	/// A scene can only hold an entity once, so each view stands its own copy.
	@State private var stage: DeviceModelStage
	@State private var objectStage: DeviceModelStage
	/// Whether a surface has been found for the model to stand on.
	@State private var placed = false
	/// A banana stands beside the model.
	@State private var showsBanana = false
	/// The banana, loaded the first time it's shown.
	@State private var banana: Entity?
	@State private var recording = false
	/// The finished recording, to save or share.
	@State private var recordingPreview: RPPreviewViewController?
	/// How far the model reaches from its middle however it's turned, so the banana stands clear of it.
	private let reach: Float

	private var accessoryManager: AccessoryManager { AccessoryManager.shared }

	init(request: DeviceModelFullScreenRequest, liveScreen: Bool) {
		self.request = request
		self.liveScreen = liveScreen
		_stage = State(initialValue: DeviceModelStage(model: request.model.clone(recursive: true), facingFront: true))
		_objectStage = State(initialValue: DeviceModelStage(model: request.model.clone(recursive: true), facingFront: true))
		let extents = request.model.visualBounds(relativeTo: nil).extents
		reach = simd_length(SIMD2(extents.x, extents.z)) / 2
	}

	/// The radio's live screen on the model and its buttons under the view.
	private var showsLiveScreen: Bool {
		liveScreen && !request.isChirpy && stage.hasScreen
	}

	var body: some View {
		ZStack {
			switch mode {
			case .room:
				DeviceModelCameraView(
					stage: stage,
					screenSource: showsLiveScreen ? accessoryManager.displayMirror : nil,
					banana: showsBanana ? banana : nil,
					bananaOffset: -(reach + 0.03),
					placed: $placed
				)
				.ignoresSafeArea()
				.gesture(turnGesture)
				.accessibilityElement(children: .ignore)
				.accessibilityLabel(String(
					localized: "3D model of \(request.name) in your space",
					comment: "Accessibility label for the camera view showing a radio's 3D model in the room; the argument is the device name"
				))
			case .object:
				DeviceModelRealityView(
					stage: objectStage,
					autoRotate: false,
					screenSource: showsLiveScreen ? accessoryManager.displayMirror : nil,
					dragsTilt: true
				)
				.background(Color(white: 0.92))
				.ignoresSafeArea()
				.accessibilityElement(children: .ignore)
				.accessibilityLabel(String(
					localized: "3D model of \(request.name)",
					comment: "Accessibility label for the rotating 3D model of a radio; the argument is the device name"
				))
			}

			// Out of the recording, apart from the button that stops it.
			VStack(spacing: 16) {
				if !recording {
					topBar
				}
				Spacer()
				if mode == .room, !placed, !recording {
					Text("Point the camera at a table or the floor.", comment: "Hint in the camera view while it looks for a surface to stand the radio's 3D model on")
						.font(.callout)
						.padding(12)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				if showsLiveScreen, !recording {
					DeviceRemoteControl { event in
						Task { await accessoryManager.sendDisplayInput(event) }
					}
					.padding(16)
					.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
				}
				recordButton
			}
			.padding()
		}
		.sheet(item: $recordingPreview) { preview in
			RecordingPreview(controller: preview)
				.ignoresSafeArea()
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
		.onDisappear {
			DeviceModelARSessions.shared.closed += 1
			accessoryManager.stopDisplayMirror(for: .deviceModelAR)
			if recording {
				RPScreenRecorder.shared().stopRecording { _, _ in }
			}
		}
		// Back in the room the model lands again, turned to face the camera.
		.onChange(of: mode) { _, mode in
			if mode == .room { placed = false }
		}
		.task(id: showsBanana) {
			if showsBanana, banana == nil {
				banana = await BananaForScale.standing()
			}
		}
	}

	/// The banana button, the AR and Object views, Share and Close.
	private var topBar: some View {
		VStack(spacing: 12) {
			HStack {
				Picker(selection: $mode) {
					Text("AR", comment: "Tab in the AR view: the radio's 3D model in the room through the camera").tag(Mode.room)
					Text("Object", comment: "Tab in the AR view: the radio's 3D model on its own, without the camera").tag(Mode.object)
				} label: {
					Text("View", comment: "Accessibility label for the AR and Object tabs in the AR view")
				}
				.pickerStyle(.segmented)
				.frame(maxWidth: 200)
				Spacer()
				if let fileURL = request.fileURL {
					ShareLink(item: fileURL) {
						Label("Share", systemImage: "square.and.arrow.up")
							.labelStyle(.iconOnly)
							.font(.body.weight(.semibold))
							.frame(width: 36, height: 36)
							.background(.ultraThinMaterial, in: Circle())
					}
					.buttonStyle(.plain)
				}
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
			if mode == .room {
				HStack {
					Toggle(isOn: $showsBanana) {
						Label {
							Text("Banana for Scale", comment: "Cinema: button on the card beside a device model on the stand; lays a real-size banana beside it")
						} icon: {
							Image("custom.banana")
						}
					}
					.toggleStyle(OverCameraToggleStyle())
					Spacer()
				}
			}
		}
	}

	/// Records the screen, without the controls, like Quick Look's record button. When it stops, the
	/// recording opens to save or share.
	private var recordButton: some View {
		Button {
			if recording {
				RPScreenRecorder.shared().stopRecording { preview, _ in
					Task { @MainActor in
						recording = false
						recordingPreview = preview
					}
				}
			} else {
				RPScreenRecorder.shared().startRecording { error in
					Task { @MainActor in
						recording = error == nil
					}
				}
			}
		} label: {
			ZStack {
				Circle()
					.strokeBorder(.white, lineWidth: 4)
					.frame(width: 64, height: 64)
				RoundedRectangle(cornerRadius: recording ? 6 : 26, style: .continuous)
					.fill(.red)
					.frame(width: recording ? 26 : 52, height: recording ? 26 : 52)
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel(recording
			? String(localized: "Stop Recording", comment: "Button in the AR view: stop recording the screen and open the recording")
			: String(localized: "Record", comment: "Button in the AR view: record the screen with the radio's 3D model"))
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

/// A toggle button that reads over the camera picture: on a frosted background when off, filled
/// with the accent color when on.
private struct OverCameraToggleStyle: ToggleStyle {
	func makeBody(configuration: Configuration) -> some View {
		let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
		Button {
			configuration.isOn.toggle()
		} label: {
			configuration.label
				.font(.body.weight(.semibold))
				.foregroundStyle(configuration.isOn ? Color.white : Color.accentColor)
				.padding(.horizontal, 14)
				.padding(.vertical, 10)
				.background {
					if configuration.isOn {
						shape.fill(Color.accentColor)
					} else {
						shape.fill(.ultraThinMaterial)
					}
				}
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(configuration.isOn ? .isSelected : [])
	}
}

extension RPPreviewViewController: @retroactive Identifiable {}

/// ReplayKit's own screen for a finished recording, with its save and share buttons.
private struct RecordingPreview: UIViewControllerRepresentable {
	let controller: RPPreviewViewController

	func makeUIViewController(context: Context) -> RPPreviewViewController {
		controller.previewControllerDelegate = context.coordinator
		return controller
	}

	func updateUIViewController(_ controller: RPPreviewViewController, context: Context) {}

	func makeCoordinator() -> Coordinator { Coordinator() }

	final class Coordinator: NSObject, RPPreviewViewControllerDelegate {
		func previewControllerDidFinish(_ controller: RPPreviewViewController) {
			controller.dismiss(animated: true)
		}
	}
}

/// The camera view with the model standing on the first table or floor it finds, turned to face the
/// camera.
@available(iOS 18.0, *)
private struct DeviceModelCameraView: UIViewRepresentable {
	let stage: DeviceModelStage
	weak var screenSource: DisplayMirrorSession?
	/// The banana to stand beside the model, or nil for none.
	let banana: Entity?
	/// Where along x the banana's near side stands, clear of the model however it's turned.
	let bananaOffset: Float
	@Binding var placed: Bool

	private static let facingName = "DeviceModelARFacing"

	func makeUIView(context: Context) -> CameraFeedView {
		let feed = CameraFeedView()
		let view = ARView(frame: feed.bounds, cameraMode: .ar, automaticallyConfigureSession: true)
		// On iOS 27, once a non-AR RealityKit view has drawn in the app, the AR view draws a black
		// camera picture every other time it opens. It draws only the model here, over the camera
		// picture drawn underneath from the session's frames.
		view.environment.background = .color(.clear)
		view.backgroundColor = .clear
		view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		view.session.delegate = context.coordinator
		feed.addSubview(view)
		context.coordinator.feed = feed
		context.coordinator.view = view
		// Any horizontal surface; the model stands on it at its own size.
		let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.1, 0.1]))
		// Turned to face the camera when it lands, so the banana stands on the viewer's left.
		let facing = Entity()
		facing.name = Self.facingName
		facing.addChild(stage.makeStandingScene())
		anchor.addChild(facing)
		view.scene.addAnchor(anchor)
		let placed = $placed
		context.coordinator.update = view.scene.subscribe(to: SceneEvents.Update.self) { [weak stage, weak view] event in
			stage?.advance(by: Float(event.deltaTime))
			guard anchor.isAnchored, !placed.wrappedValue, let view else { return }
			let camera = facing.convert(position: view.cameraTransform.translation, from: nil)
			facing.orientation = simd_quatf(angle: atan2(camera.x, camera.z), axis: [0, 1, 0])
			placed.wrappedValue = true
		}
		return feed
	}

	func updateUIView(_ feed: CameraFeedView, context: Context) {
		stage.screenSource = screenSource
		guard let facing = context.coordinator.view?.scene.anchors.first?.children.first(where: { $0.name == Self.facingName }) else { return }
		// One banana at a time: a different one, or none, takes the last one down.
		for child in facing.children where child.name == "Banana" && child !== banana {
			child.removeFromParent()
		}
		if let banana, banana.parent !== facing {
			// On the model's left, as on the cinema's stand.
			banana.name = "Banana"
			banana.position = [bananaOffset, 0, 0]
			facing.addChild(banana)
		}
	}

	func makeCoordinator() -> Coordinator { Coordinator() }

	static func dismantleUIView(_ feed: CameraFeedView, coordinator: Coordinator) {
		coordinator.update?.cancel()
		coordinator.view?.session.pause()
	}

	/// Keeps the per-frame update running while the view is up, and passes each camera frame to the
	/// picture underneath.
	final class Coordinator: NSObject, ARSessionDelegate {
		var update: Cancellable?
		weak var feed: CameraFeedView?
		weak var view: ARView?

		func session(_ session: ARSession, didUpdate frame: ARFrame) {
			feed?.show(frame.capturedImage)
		}
	}
}

/// The camera picture, filling the view the way the AR view fills it, so the model drawn over it
/// lines up.
private final class CameraFeedView: UIView {
	private let picture = AVSampleBufferDisplayLayer()
	private var format: CMVideoFormatDescription?

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = .black
		picture.videoGravity = .resizeAspectFill
		layer.addSublayer(picture)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		// The camera's frames come in landscape, the right way up with the Home Screen's dock on the right.
		let angle: CGFloat = switch window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait {
		case .landscapeRight: 0
		case .landscapeLeft: .pi
		case .portraitUpsideDown: -.pi / 2
		default: .pi / 2
		}
		let turned = angle != 0 && angle != .pi
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		picture.setAffineTransform(.identity)
		picture.bounds = CGRect(origin: .zero, size: turned ? CGSize(width: bounds.height, height: bounds.width) : bounds.size)
		picture.position = CGPoint(x: bounds.midX, y: bounds.midY)
		picture.setAffineTransform(CGAffineTransform(rotationAngle: angle))
		CATransaction.commit()
	}

	/// Shows one camera frame.
	func show(_ image: CVPixelBuffer) {
		if format.map({ !CMVideoFormatDescriptionMatchesImageBuffer($0, imageBuffer: image) }) ?? true {
			format = nil
			CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image, formatDescriptionOut: &format)
		}
		guard let format else { return }
		var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
		var sample: CMSampleBuffer?
		CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
		guard let sample else { return }
		if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
			let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
			CFDictionarySetValue(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
		}
		let renderer = picture.sampleBufferRenderer
		if renderer.status == .failed {
			renderer.flush()
		}
		renderer.enqueue(sample)
	}
}
#endif
