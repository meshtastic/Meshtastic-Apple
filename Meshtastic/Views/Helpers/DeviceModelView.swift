//
//  DeviceModelView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import SwiftUI
import RealityKit
import OSLog
import QuickLook
#if os(iOS) && !targetEnvironment(macCatalyst)
import ARKit
#endif

/// Shows the device image with a 3D badge; tapping either switches to the device's 3D model,
/// turning slowly. The model is only fetched once asked for. If it can't be loaded, the badge goes
/// away and the image stays. Once it's showing, "View in your space" stands it in the room at real
/// size (in the Vision Pro cinema, on a stand in the tent), and tapping it seven times swaps it for
/// Chirpy. For the connected radio, its live screen shows on the model's display.
@available(iOS 18.0, macCatalyst 18.0, visionOS 1.0, *)
struct DeviceModelView<Placeholder: View>: View {
	let modelName: String
	let deviceName: String
	/// The node it's a model of, for the live readings beside it in the Vision Pro cinema.
	var nodeNum: Int64?
	/// Show the radio's own screen on the model. Only for the connected radio, while it's connected
	/// and reports a display.
	var liveScreen = false
	@ViewBuilder let placeholder: () -> Placeholder

	/// Not observed: every change to the connection, down to the RX/TX lights, would redraw this view,
	/// and in a list row that rebuilds the full-screen sheet and its 3D view. `liveScreen` carries
	/// the connection state it needs.
	private var accessoryManager: AccessoryManager { AccessoryManager.shared }
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var showsModel = false
	@State private var isLoading = false
	@State private var unavailable = false
	@State private var stage: DeviceModelStage?
	/// The model as loaded, kept out of any scene so the full-screen view can have its own copy.
	@State private var loadedModel: Entity?
	/// Full screen opened here, when nothing above offers to present it.
	@State private var localFullScreen: DeviceModelFullScreenRequest?
	@Environment(\.presentDeviceModelFullScreen) private var presentFullScreen
	/// The file the model came from, handed to Quick Look for "View in your space".
	@State private var modelURL: URL?
	@State private var quickLookURL: URL?
	@State private var showsChirpy = false
	@State private var chirpyTaps = 0
	@State private var lastChirpyTap = Date.distantPast

	/// Seven taps on the model within this long of each other swap it for Chirpy, or back.
	private static var chirpyTapCount: Int { 7 }
	private static var chirpyTapWindow: TimeInterval { 1.5 }

	private var shownModelName: String { showsChirpy ? DeviceModelCatalog.chirpy : modelName }
	private var shownName: String { showsChirpy ? "Chirpy" : deviceName }

	/// Stream the screen while the model with a display is showing and the app is in front.
	private var wantsMirror: Bool {
		liveScreen && stage?.hasScreen == true && scenePhase == .active
	}

	var body: some View {
		// Bottom left: the supported-hardware rosette sits bottom right on the same image.
		ZStack(alignment: .bottomLeading) {
			ZStack {
				placeholder()
					.opacity(stage == nil ? 1 : 0)
					.accessibilityHidden(stage != nil)
				if let stage {
					DeviceModelRealityView(
						stage: stage,
						autoRotate: !reduceMotion,
						screenSource: liveScreen ? accessoryManager.displayMirror : nil
					)
						// RealityView adds its content once, so a new model needs a new view.
						.id(ObjectIdentifier(stage))
						.transition(.opacity)
						.accessibilityElement(children: .ignore)
						.accessibilityLabel(String(
							localized: "3D model of \(shownName)",
							comment: "Accessibility label for the rotating 3D model of a radio; the argument is the device name"
						))
				}
			}
			.animation(.easeInOut(duration: 0.35), value: stage == nil)
			.contentShape(Rectangle())
			.onTapGesture {
				// The image switches to the model; on the model, touches rotate and zoom it, and
				// enough taps in a row swap in Chirpy.
				if stage == nil {
					if !unavailable { showsModel = true }
				} else {
					countChirpyTap()
				}
			}
			if !unavailable {
				toggleButton
					.padding(8)
			}
		}
		// The model's own controls in the top corners: AR on the left, full screen on the right.
		.overlay(alignment: .topLeading) {
			if stage != nil, modelURL != nil, Self.canViewInSpace {
				viewInSpaceButton
					.padding(8)
			}
		}
		.overlay(alignment: .topTrailing) {
			if stage != nil, loadedModel != nil {
				fullScreenButton
					.padding(8)
			}
		}
		.task(id: ModelRequest(showsModel: showsModel, name: shownModelName)) {
			guard showsModel else {
				stage = nil
				loadedModel = nil
				modelURL = nil
				return
			}
			let name = shownModelName
			isLoading = true
			defer { isLoading = false }
			guard let url = await DeviceModelSource.shared.localURL(for: name) else {
				if !Task.isCancelled { giveUp() }
				return
			}
			guard !Task.isCancelled else { return }
			do {
				let entity = try await Entity(contentsOf: url)
				guard !Task.isCancelled else { return }
				loadedModel = entity.clone(recursive: true)
				stage = DeviceModelStage(model: entity)
				modelURL = url
			} catch {
				// A different model was picked while this one loaded; its failure says
				// nothing about the new one, which would stay marked unavailable.
				guard !Task.isCancelled else { return }
				Logger.services.error("Device model \(name, privacy: .public) failed to open: \(error.localizedDescription, privacy: .public)")
				// A damaged download would otherwise fail the same way every time.
				await DeviceModelSource.shared.discardCachedFile(for: name)
				giveUp()
			}
		}
		// A task rather than onChange, so it runs again when the view comes back on screen.
		.task(id: wantsMirror) {
			if wantsMirror {
				accessoryManager.startDisplayMirror(for: .deviceModel)
			} else {
				accessoryManager.stopDisplayMirror(for: .deviceModel)
			}
		}
		.onDisappear {
			accessoryManager.stopDisplayMirror(for: .deviceModel)
		}
		.onChange(of: modelName) {
			showsModel = false
			showsChirpy = false
			unavailable = false
		}
		#if os(iOS)
		.quickLookPreview($quickLookURL)
		#endif
		.sheet(item: $localFullScreen) { request in
			DeviceModelFullScreen(request: request, liveScreen: liveScreen)
		}
	}

	private var fullScreenButton: some View {
		Button {
			guard let loadedModel else { return }
			let request = DeviceModelFullScreenRequest(model: loadedModel, name: shownName, isChirpy: showsChirpy)
			if let presentFullScreen {
				presentFullScreen(request)
			} else {
				localFullScreen = request
			}
		} label: {
			Image(systemName: "arrow.up.left.and.arrow.down.right")
				.font(.body.weight(.semibold))
				.frame(width: 36, height: 36)
				.background(.ultraThinMaterial, in: Circle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(String(localized: "Full Screen", comment: "Button on a radio's 3D model: open the model full screen"))
	}

	private struct ModelRequest: Equatable {
		let showsModel: Bool
		let name: String
	}

	/// Where Quick Look can put a model in the room: iPhones and iPads that run world tracking,
	/// and Vision Pro. A Mac has no camera view to place it in.
	private static var canViewInSpace: Bool {
		#if os(visionOS)
		return true
		#elseif os(iOS) && !targetEnvironment(macCatalyst)
		return ARWorldTrackingConfiguration.isSupported
		#else
		return false
		#endif
	}

	private var viewInSpaceButton: some View {
		Button {
			guard let modelURL else { return }
			#if os(visionOS)
			if let showModel = CinemaScene.showModel {
				showModel(CinemaModelRequest(modelName: shownModelName, deviceName: shownName, nodeNum: showsChirpy ? nil : nodeNum))
			} else {
				// A Quick Look window of its own, which can be set down anywhere in the room.
				_ = PreviewApplication.open(urls: [modelURL])
			}
			#else
			// Quick Look shows the model at its own size, which is the real one.
			quickLookURL = modelURL
			#endif
		} label: {
			Image(systemName: "arkit")
				.font(.body.weight(.semibold))
				.frame(width: 36, height: 36)
				.background(.ultraThinMaterial, in: Circle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(String(localized: "View in your space", comment: "Button on a radio's 3D model: place the model in the room around you at real size"))
	}

	/// Counts taps on the model; a run of seven swaps the device for Chirpy, or Chirpy back.
	private func countChirpyTap() {
		let now = Date.now
		chirpyTaps = now.timeIntervalSince(lastChirpyTap) < Self.chirpyTapWindow ? chirpyTaps + 1 : 1
		lastChirpyTap = now
		guard chirpyTaps >= Self.chirpyTapCount else { return }
		chirpyTaps = 0
		showsChirpy.toggle()
	}

	private var toggleButton: some View {
		Button {
			showsModel.toggle()
		} label: {
			Group {
				if isLoading {
					ProgressView()
				} else {
					Image(systemName: showsModel ? "photo" : "rotate.3d")
						.font(.body.weight(.semibold))
				}
			}
			.frame(width: 36, height: 36)
			.background(.ultraThinMaterial, in: Circle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(showsModel
			? String(localized: "Show photo", comment: "Button on the device image: switch from the 3D model back to the picture")
			: String(localized: "Show 3D model", comment: "Button on the device image: switch from the picture to the device's 3D model"))
	}

	/// No model to show: back to the image, without the badge.
	private func giveUp() {
		showsModel = false
		unavailable = true
	}
}

/// A model to open full screen.
struct DeviceModelFullScreenRequest: Identifiable {
	let id = UUID()
	let model: Entity
	let name: String
	let isChirpy: Bool
}

extension EnvironmentValues {
	/// Opens a 3D model full screen from outside the list it sits in. A sheet attached to a list
	/// row is rebuilt whenever the list rebuilds that row, and its 3D view with it.
	@Entry var presentDeviceModelFullScreen: ((DeviceModelFullScreenRequest) -> Void)?
}

/// The model in a large sheet, held still and facing you, with the radio's buttons under it and a
/// zoom button that steps from the whole model to the case to the screen.
@available(iOS 18.0, macCatalyst 18.0, visionOS 1.0, *)
struct DeviceModelFullScreen: View {
	let request: DeviceModelFullScreenRequest
	/// Show the radio's live screen and its buttons: the connected radio, while connected, with a display.
	let liveScreen: Bool

	@Environment(\.dismiss) private var dismiss
	/// A scene can only hold an entity once, so this view turns its own copy.
	@State private var stage: DeviceModelStage
	/// How close the model is: the zoom button steps through the stage's levels.
	@State private var zoomLevel: DeviceModelStage.ZoomLevel = .model

	private var accessoryManager: AccessoryManager { AccessoryManager.shared }

	init(request: DeviceModelFullScreenRequest, liveScreen: Bool) {
		self.request = request
		self.liveScreen = liveScreen && !request.isChirpy
		_stage = State(initialValue: DeviceModelStage(model: request.model.clone(recursive: true), facingFront: true))
	}

	var body: some View {
		NavigationStack {
			VStack(spacing: 16) {
				DeviceModelRealityView(
					stage: stage,
					autoRotate: false,
					screenSource: liveScreen ? accessoryManager.displayMirror : nil,
					dragsTilt: true
				)
				.accessibilityElement(children: .ignore)
				.accessibilityLabel(String(
					localized: "3D model of \(request.name)",
					comment: "Accessibility label for the rotating 3D model of a radio; the argument is the device name"
				))
				if liveScreen {
					DeviceRemoteControl { event in
						Task { await accessoryManager.sendDisplayInput(event) }
					}
				}
			}
			.padding()
			// Drags turn the model, so they mustn't close the sheet.
			.interactiveDismissDisabled()
			.navigationTitle(request.name)
			#if !os(macOS)
			.navigationBarTitleDisplayMode(.inline)
			#endif
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Label("Close", systemImage: "xmark")
					}
				}
				if stage.zoomLevels.count > 1 {
					ToolbarItem(placement: .primaryAction) {
						zoomButton
					}
				}
			}
		}
		.presentationDetents([.large])
	}

	/// Steps in from the whole model to the case without its antenna, then the screen, then back out.
	private var zoomButton: some View {
		let levels = stage.zoomLevels
		let next = levels[((levels.firstIndex(of: zoomLevel) ?? 0) + 1) % levels.count]
		return Button {
			stage.zoom(to: next)
			zoomLevel = next
		} label: {
			switch next {
			case .model:
				Label("Zoom Out", systemImage: "minus.magnifyingglass")
			case .body:
				Label("Zoom to Case", systemImage: "plus.magnifyingglass")
			case .screen:
				Label("Zoom to Screen", systemImage: "plus.magnifyingglass")
			}
		}
	}

}

@available(iOS 18.0, macCatalyst 18.0, visionOS 1.0, *)
private struct DeviceModelRealityView: View {
	let stage: DeviceModelStage
	let autoRotate: Bool
	/// Where the radio's live screen comes from. The stage reads it as it draws, so a new picture
	/// doesn't redraw this view or the list around it.
	let screenSource: DisplayMirrorSession?
	/// Vertical drags tilt the model. Off in a list, where they have to scroll it.
	var dragsTilt = false

	#if os(visionOS)
	@Environment(\.physicalMetrics) private var metrics
	#else
	@Environment(\.colorScheme) private var colorScheme
	#endif

	var body: some View {
		GeometryReader { proxy in
			RealityView { content in
				content.add(stage.makeScene())
				#if !os(visionOS)
				content.camera = .virtual
				#endif
				stage.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak stage] event in
					stage?.advance(by: Float(event.deltaTime))
				}
			} update: { _ in
				stage.autoRotate = autoRotate
				stage.screenSource = screenSource
				#if os(visionOS)
				stage.viewHalfExtents = [
					Float(metrics.convert(proxy.size.width / 2, to: .meters)),
					Float(metrics.convert(proxy.size.height / 2, to: .meters))
				]
				#else
				// The camera shows a sphere of radius 1 top to bottom; the width follows the view's shape.
				let halfHeight: Float = 1.02 / cos(15 * .pi / 180)
				stage.viewHalfExtents = [halfHeight * Float(proxy.size.width / max(proxy.size.height, 1)), halfHeight]
				#endif
				#if os(visionOS)
				// Real meters in a window: fit the model's sphere into the view's shorter side.
				let side = min(proxy.size.width, proxy.size.height)
				stage.fitRadius = Float(metrics.convert(side, to: .meters)) * 0.42
				#endif
			}
		}
		.background { backdrop }
		.contentShape(Rectangle())
		// Simultaneous so a drag that starts on the model can still scroll the list.
		.simultaneousGesture(rotateGesture)
		.simultaneousGesture(zoomGesture)
	}

	/// Most radios are black, and vanish against a dark card. In dark mode, and always on Vision Pro
	/// where the window's glass is dark, they stand on a soft gray, lighter in the middle like a
	/// studio backdrop.
	@ViewBuilder
	private var backdrop: some View {
		#if os(visionOS)
		let dark = true
		#else
		let dark = colorScheme == .dark
		#endif
		if dark {
			RadialGradient(
				colors: [Color(white: 0.52), Color(white: 0.30)],
				center: .center,
				startRadius: 0,
				endRadius: 160
			)
			.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}

	/// Horizontal drags spin the model; mostly-vertical drags are left alone so the list still
	/// scrolls.
	private var rotateGesture: some Gesture {
		DragGesture(minimumDistance: 8)
			.onChanged { value in
				if !stage.isDragging {
					guard dragsTilt || abs(value.translation.width) > abs(value.translation.height) else { return }
					stage.beginDrag()
				}
				stage.drag(by: value.translation)
			}
			.onEnded { _ in stage.endDrag() }
	}

	private var zoomGesture: some Gesture {
		MagnifyGesture()
			.onChanged { value in stage.zoom(by: Float(value.magnification)) }
			.onEnded { _ in stage.endZoom() }
	}
}

/// The RealityKit side: a pivot that turns, holding the model scaled and centered inside it.
@available(iOS 18.0, macCatalyst 18.0, visionOS 1.0, *)
@MainActor
final class DeviceModelStage {
	/// Radians per second while turning on its own.
	private static let spinSpeed: Float = 0.45
	/// A slight downward look so the face and an edge both show.
	private static let restingPitch: Float = 0.22

	/// The model as loaded. Each view showing the stage builds its own copy from it.
	private let source: Entity
	/// The entities of the view showing the stage now, rebuilt by `makeScene()`.
	private(set) var pivot = Entity()
	private var holder = Entity()
	#if !os(visionOS)
	private(set) var camera = Entity()
	#endif
	var subscription: EventSubscription?
	var autoRotate = true

	private var radius: Float = 1
	/// Half the model's bounding box diagonal: the farthest any part gets from its center,
	/// however it's turned.
	private var sphereRadius: Float = 1
	private var yaw: Float = -0.5
	private var pitch: Float = DeviceModelStage.restingPitch
	private var dragStartYaw: Float = 0
	private var dragStartPitch: Float = 0
	private var zoomFactor: Float = 1
	/// The point of the model kept at the middle of the view, from its center: the screen when zoomed to it.
	private var focus: SIMD2<Float> = .zero
	/// The model's center, in its own space.
	private var modelCenter: SIMD3<Float> = .zero
	/// Half the view's width and height at the model, in scene units, set by the view.
	var viewHalfExtents: SIMD2<Float> = [1, 1] {
		didSet { if viewHalfExtents != oldValue { refit() } }
	}
	/// The level the model is fitted to, kept as the view changes size, until a drag or pinch
	/// takes over.
	private var fitLevel: ZoomLevel?
	/// The whole model, in its own space.
	private var modelBounds: BoundingBox
	private var zoomStart: Float = 1
	private var userTookOver = false
	private(set) var isDragging = false

	/// The front of the model's `Screen` part, in the model's own space, where the radio's live
	/// screen is drawn.
	private var screenBounds: BoundingBox?
	private var screenPlane = ModelEntity()
	private var screenTexture: TextureResource?
	private var screenShape: ScreenShape?
	private var lastScreenImage: CGImage?

	var hasScreen: Bool { screenBounds != nil }
	/// The radio's live screen, drawn on the model each frame it changes.
	weak var screenSource: DisplayMirrorSession?
	/// The model without its antenna, in its own space, when it has one.
	private var bodyBounds: BoundingBox?

	enum ZoomLevel {
		/// The whole model, antenna and all.
		case model
		/// The case, with the antenna out of view.
		case body
		/// Just the screen.
		case screen
	}

	/// The levels the zoom button steps through, closest last.
	var zoomLevels: [ZoomLevel] {
		var levels: [ZoomLevel] = [.model]
		if bodyBounds != nil { levels.append(.body) }
		if screenBounds != nil { levels.append(.screen) }
		return levels
	}

	/// The radius the model's bounding sphere is scaled to: scene units on iOS, where the camera
	/// is placed to fit 1, and meters on visionOS, where the view sets it from its size.
	#if os(visionOS)
	var fitRadius: Float = 0.07 {
		didSet { if fitRadius != oldValue { refit() } }
	}
	#else
	var fitRadius: Float = 1 {
		didSet { if fitRadius != oldValue { refit() } }
	}
	#endif

	/// `facingFront` starts it square on to the viewer, the screen readable, instead of turned to show an edge.
	init(model: Entity, facingFront: Bool = false) {
		if facingFront {
			yaw = 0
			pitch = 0
			fitLevel = .model
		}
		source = model
		let bounds = model.visualBounds(relativeTo: nil)
		modelBounds = bounds
		// Turning about Y sweeps the footprint's diagonal, so that and the height are what has
		// to fit; a full bounding sphere leaves tall, thin devices looking small.
		let extents = bounds.extents
		let sweep = simd_length(SIMD2(extents.x, extents.z)) / 2
		radius = max(sweep, extents.y / 2, 0.0001)
		sphereRadius = max(simd_length(extents) / 2, radius)
		modelCenter = bounds.center
		if let screen = model.findEntity(named: "Screen") {
			let screenBox = screen.visualBounds(relativeTo: model)
			if !screenBox.isEmpty {
				screenBounds = screenBox
			}
		}
		// The model generator names antenna parts with these words.
		var body = BoundingBox.empty
		var hasAntenna = false
		model.visit { part in
			guard part.components.has(ModelComponent.self) else { return }
			let name = part.name.lowercased()
			if ["antenna", "whip", "appendage"].contains(where: { name.contains($0) }) {
				hasAntenna = true
			} else {
				body = body.union(part.visualBounds(recursive: false, relativeTo: model))
			}
		}
		if hasAntenna, !body.isEmpty {
			bodyBounds = body
		}
	}

	/// A fresh set of entities for a view to show, posed as the stage is now. SwiftUI can rebuild a
	/// view while the old one is still up, and tearing the old one down takes its entities with it,
	/// so views never share them.
	func makeScene() -> Entity {
		let root = Entity()
		let model = source.clone(recursive: true)
		model.position = -modelCenter
		pivot = Entity()
		holder = Entity()
		screenPlane = ModelEntity()
		screenTexture = nil
		screenShape = nil
		lastScreenImage = nil
		if screenBounds != nil {
			screenPlane.isEnabled = false
			model.addChild(screenPlane)
		}
		holder.addChild(model)
		pivot.addChild(holder)
		root.addChild(pivot)
		applyScale()
		applyOrientation()

		#if !os(visionOS)
		camera = Entity()
		let fov: Float = 30
		var lens = PerspectiveCameraComponent()
		lens.fieldOfViewInDegrees = fov
		lens.near = 0.05
		lens.far = 50
		camera.components.set(lens)
		// Back off far enough that a sphere of radius 1 fits the vertical field of view.
		camera.position = [0, 0, Self.cameraDistance]

		// RealityKit's default lighting washes dark plastic out to mid gray, so light the model
		// from a dim studio-style environment instead.
		if let studio = Self.studioEnvironment {
			let environment = Entity()
			environment.components.set(ImageBasedLightComponent(source: .single(studio), intensityExponent: 0.7))
			camera.addChild(environment)
			let receiver = ImageBasedLightReceiverComponent(imageBasedLight: environment)
			model.components.set(receiver)
			model.visit { $0.components.set(receiver) }
		}

		let key = Entity()
		var light = DirectionalLightComponent()
		light.intensity = 1_400
		key.components.set(light)
		key.look(at: .zero, from: [-1.5, 2.5, 3], relativeTo: nil)
		camera.addChild(key, preservingWorldTransform: true)
		root.addChild(camera)
		#endif
		return root
	}

	#if !os(visionOS)
	/// Far enough back that a sphere of radius 1 fits the camera's 30° vertical field of view.
	private static let cameraDistance: Float = 1.02 / sin(15 * .pi / 180)

	/// A soft gray environment: brighter overhead, falling off toward the floor.
	private static let studioEnvironment: EnvironmentResource? = {
		let width = 64, height = 32
		var pixels = [UInt8](repeating: 0, count: width * height)
		for row in 0..<height {
			let up = 1 - Double(row) / Double(height - 1)
			let level = 0.12 + 0.68 * pow(up, 1.6)
			for column in 0..<width {
				pixels[row * width + column] = UInt8(level * 255)
			}
		}
		guard let provider = CGDataProvider(data: Data(pixels) as CFData),
			let image = CGImage(
				width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
				space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
				provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
			) else { return nil }
		return try? EnvironmentResource(equirectangular: image)
	}()
	#endif

	func advance(by seconds: Float) {
		// A cheap check: it only redraws when the radio has sent a new picture.
		showScreen(screenSource?.image)
		guard autoRotate, !userTookOver else { return }
		yaw += Self.spinSpeed * min(seconds, 0.1)
		applyOrientation()
	}

	func beginDrag() {
		isDragging = true
		userTookOver = true
		fitLevel = nil
		dragStartYaw = yaw
		dragStartPitch = pitch
	}

	func drag(by translation: CGSize) {
		guard isDragging else { return }
		yaw = dragStartYaw + Float(translation.width) * 0.012
		pitch = min(max(dragStartPitch + Float(translation.height) * 0.008, -1.2), 1.2)
		applyOrientation()
	}

	func endDrag() {
		isDragging = false
	}

	func zoom(by magnification: Float) {
		userTookOver = true
		fitLevel = nil
		zoomFactor = min(max(zoomStart * magnification, 0.6), max(2.2, zoomStart))
		applyScale()
	}

	func endZoom() {
		zoomStart = zoomFactor
	}

	struct ScreenShape: Equatable {
		let width: Float
		let height: Float
		let turned: Bool
	}

	/// The picture's size on a display `slotWidth` by `slotHeight`: its own shape, as large as fits,
	/// turned a quarter when the display is mounted the other way round.
	nonisolated static func screenShape(imageWidth: Int, imageHeight: Int, slotWidth: Float, slotHeight: Float) -> ScreenShape {
		let aspect = Float(imageWidth) / Float(max(imageHeight, 1))
		let turned = (aspect > 1.05 && slotHeight > slotWidth * 1.05) || (aspect < 0.95 && slotWidth > slotHeight * 1.05)
		// The picture's width runs along the display's height when it's turned.
		let along = turned ? slotHeight : slotWidth
		let across = turned ? slotWidth : slotHeight
		let width = min(along, across * aspect)
		return ScreenShape(width: width, height: width / aspect, turned: turned)
	}

	/// Draws the radio's screen on the model's display, or hides it. The picture keeps its own shape
	/// inside the display, turned a quarter if the display is mounted the other way round, with no
	/// lighting so it reads like a lit screen.
	func showScreen(_ image: CGImage?) {
		guard let screenBounds else { return }
		guard let image else {
			screenPlane.isEnabled = false
			lastScreenImage = nil
			return
		}
		guard image !== lastScreenImage else { return }
		lastScreenImage = image
		let shape = Self.screenShape(
			imageWidth: image.width,
			imageHeight: image.height,
			slotWidth: screenBounds.extents.x,
			slotHeight: screenBounds.extents.y
		)

		do {
			if let screenTexture {
				try screenTexture.replace(withImage: image, options: .init(semantic: .color))
			} else {
				let texture = try TextureResource(image: image, options: .init(semantic: .color))
				screenTexture = texture
				var material = UnlitMaterial()
				material.color = .init(tint: .white, texture: .init(texture, sampler: Self.nearestSampler))
				screenPlane.model = ModelComponent(mesh: .generatePlane(width: 1, height: 1), materials: [material])
			}
		} catch {
			Logger.services.error("Device model screen: couldn't make a texture: \(error.localizedDescription, privacy: .public)")
			return
		}
		if shape != screenShape {
			screenShape = shape
			screenPlane.scale = [shape.width, shape.height, 1]
			screenPlane.orientation = shape.turned ? simd_quatf(angle: .pi / 2, axis: [0, 0, 1]) : simd_quatf()
			// Just in front of the display's face, so the case around it can't cover it.
			let center = screenBounds.center
			screenPlane.position = [center.x, center.y, screenBounds.max.z + 0.00005]
		}
		screenPlane.isEnabled = true
	}

	/// Each radio pixel stays a crisp square, however close the camera gets.
	private static let nearestSampler: MaterialParameters.Texture.Sampler = {
		let descriptor = MTLSamplerDescriptor()
		descriptor.minFilter = .nearest
		descriptor.magFilter = .nearest
		descriptor.mipFilter = .notMipmapped
		return MaterialParameters.Texture.Sampler(descriptor)
	}()

	/// Faces the model square on and zooms to `level`: the part fills as much of the view as fits.
	/// The whole model is fitted by its own shape rather than the sphere it turns in, so a wide
	/// board fills a narrow view instead of running off its sides.
	func zoom(to level: ZoomLevel) {
		fitLevel = level
		switch level {
		case .model:
			zoom(toFit: modelBounds)
		case .body:
			if let bodyBounds { zoom(toFit: bodyBounds) }
		case .screen:
			if let screenBounds { zoom(toFit: screenBounds) }
		}
	}

	private func zoom(toFit box: BoundingBox) {
		yaw = 0
		pitch = 0
		let half = SIMD2(box.extents.x, box.extents.y) / 2
		let room = viewHalfExtents * 0.9
		// The part's front is nearer the camera than the model's middle, so perspective makes it
		// look bigger as it's scaled up. At scale s it sits s * front nearer, and what the view shows
		// there shrinks by (distance - s * front) / distance. Solve for the s that fits.
		let front = max(box.max.z - modelCenter.z, 0)
		#if os(visionOS)
		let perspective: Float = 0
		#else
		let perspective = front / Self.cameraDistance
		#endif
		let fitX = room.x / (half.x + room.x * perspective)
		let fitY = room.y / (half.y + room.y * perspective)
		zoomFactor = min(fitX, fitY) / (fitRadius / radius)
		zoomStart = zoomFactor
		let center = box.center - modelCenter
		focus = [center.x, center.y]
		applyScale()
		applyOrientation()
	}

	/// Fits the model to its level again after the view changes size, or just rescales it.
	private func refit() {
		if let fitLevel {
			zoom(to: fitLevel)
		} else {
			applyScale()
		}
	}

	private func applyScale() {
		let scale = fitRadius / radius * zoomFactor
		holder.scale = .init(repeating: scale)
		holder.position = [-focus.x * scale, -focus.y * scale, 0]
		#if os(visionOS)
		// A window cuts off whatever is behind its surface, so the model stands just in front of
		// it however it's turned or tilted.
		pivot.position = [0, 0, fitRadius / radius * zoomFactor * sphereRadius]
		#endif
	}

	private func applyOrientation() {
		pivot.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
	}
}

@available(iOS 18.0, macCatalyst 18.0, visionOS 1.0, *)
private extension Entity {
	/// Calls `body` on every descendant.
	func visit(_ body: (Entity) -> Void) {
		for child in children {
			body(child)
			child.visit(body)
		}
	}
}
