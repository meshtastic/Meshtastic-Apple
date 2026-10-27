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
/// Chirpy.
@available(iOS 18.0, macCatalyst 18.0, visionOS 1.0, *)
struct DeviceModelView<Placeholder: View>: View {
	let modelName: String
	let deviceName: String
	/// The node it's a model of, for the live readings beside it in the Vision Pro cinema.
	var nodeNum: Int64?
	@ViewBuilder let placeholder: () -> Placeholder

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var showsModel = false
	@State private var isLoading = false
	@State private var unavailable = false
	@State private var stage: DeviceModelStage?
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

	var body: some View {
		// Bottom left: the supported-hardware rosette sits bottom right on the same image.
		ZStack(alignment: .bottomLeading) {
			ZStack {
				placeholder()
					.opacity(stage == nil ? 1 : 0)
					.accessibilityHidden(stage != nil)
				if let stage {
					DeviceModelRealityView(stage: stage, autoRotate: !reduceMotion)
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
				HStack(spacing: 8) {
					toggleButton
					if stage != nil, modelURL != nil, Self.canViewInSpace {
						viewInSpaceButton
					}
				}
				.padding(8)
			}
		}
		.task(id: ModelRequest(showsModel: showsModel, name: shownModelName)) {
			guard showsModel else {
				stage = nil
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
		.onChange(of: modelName) {
			showsModel = false
			showsChirpy = false
			unavailable = false
		}
		#if os(iOS)
		.quickLookPreview($quickLookURL)
		#endif
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

@available(iOS 18.0, macCatalyst 18.0, visionOS 1.0, *)
private struct DeviceModelRealityView: View {
	let stage: DeviceModelStage
	let autoRotate: Bool

	#if os(visionOS)
	@Environment(\.physicalMetrics) private var metrics
	#else
	@Environment(\.colorScheme) private var colorScheme
	#endif

	var body: some View {
		GeometryReader { proxy in
			RealityView { content in
				content.add(stage.pivot)
				#if !os(visionOS)
				content.camera = .virtual
				content.add(stage.camera)
				#endif
				stage.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak stage] event in
					stage?.advance(by: Float(event.deltaTime))
				}
			} update: { _ in
				stage.autoRotate = autoRotate
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
					guard abs(value.translation.width) > abs(value.translation.height) else { return }
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

	let pivot = Entity()
	private let holder = Entity()
	#if !os(visionOS)
	let camera = Entity()
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
	private var zoomStart: Float = 1
	private var userTookOver = false
	private(set) var isDragging = false

	/// The radius the model's bounding sphere is scaled to: scene units on iOS, where the camera
	/// is placed to fit 1, and meters on visionOS, where the view sets it from its size.
	#if os(visionOS)
	var fitRadius: Float = 0.07 {
		didSet { if fitRadius != oldValue { applyScale() } }
	}
	#else
	var fitRadius: Float = 1 {
		didSet { if fitRadius != oldValue { applyScale() } }
	}
	#endif

	init(model: Entity) {
		let bounds = model.visualBounds(relativeTo: nil)
		// Turning about Y sweeps the footprint's diagonal, so that and the height are what has
		// to fit; a full bounding sphere leaves tall, thin devices looking small.
		let extents = bounds.extents
		let sweep = simd_length(SIMD2(extents.x, extents.z)) / 2
		radius = max(sweep, extents.y / 2, 0.0001)
		sphereRadius = max(simd_length(extents) / 2, radius)
		model.position = -bounds.center
		holder.addChild(model)
		pivot.addChild(holder)
		applyScale()
		applyOrientation()

		#if !os(visionOS)
		let fov: Float = 30
		var lens = PerspectiveCameraComponent()
		lens.fieldOfViewInDegrees = fov
		lens.near = 0.05
		lens.far = 50
		camera.components.set(lens)
		// Back off far enough that a sphere of radius 1 fits the vertical field of view.
		let distance = 1.02 / sin(fov / 2 * .pi / 180)
		camera.position = [0, 0, distance]

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
		#endif
	}

	#if !os(visionOS)
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
		guard autoRotate, !userTookOver else { return }
		yaw += Self.spinSpeed * min(seconds, 0.1)
		applyOrientation()
	}

	func beginDrag() {
		isDragging = true
		userTookOver = true
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
		zoomFactor = min(max(zoomStart * magnification, 0.6), 2.2)
		applyScale()
	}

	func endZoom() {
		zoomStart = zoomFactor
	}

	private func applyScale() {
		holder.scale = .init(repeating: fitRadius / radius * zoomFactor)
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
