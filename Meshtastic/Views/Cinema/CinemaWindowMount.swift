//
//  CinemaWindowMount.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
#if os(visionOS)
import ARKit
import CinemaContent
import OSLog
import QuartzCore
import RealityKit
import UIKit

/// Sets the main window into the tent's front wall. Nothing can pin a window in place, so the wall
/// comes to the window instead: a black frame sits just behind the window and follows it, and the
/// front wall, as its own flat image, sits just behind that at the window's depth. The painted
/// tent turns so its front wall faces the window. While the window is moving the wall fades out,
/// and once it has been still for a moment the tent turns to it and the wall fades back in.
@MainActor
final class CinemaWindowMount {
	/// Turns the tent with the window while it is being dragged, instead of once it has settled.
	/// For comparing the two on a device.
	static let turnsLive = false

	/// The frame round the window and the dark backing behind it. Goes in the scene's world, not
	/// the stage, since it follows the window rather than the painting.
	let frame = Entity()

	/// How far behind the window the frame and the wall sit, in meters.
	private static let frameGap: Float = 0.01
	private static let wallGap: Float = 0.02
	/// How wide the frame is round the window, in meters.
	private static let frameWidth: Float = 0.04
	/// A visionOS window's corner radius, in the window's points.
	private static let windowCornerRadius: Float = 46
	/// How long the window must be still before the tent turns to it, and how long the turn takes.
	private static let settleTime: TimeInterval = 0.5
	private static let turnTime: TimeInterval = 0.4

	private var wall: ModelEntity?
	private var wallShape: CinemaAnchors.FrontWall?
	private var wallOpacity: Float = 0
	private var frameMaterial: UnlitMaterial?
	private var frameSize: SIMD2<Float> = .zero
	private var snapFrame = true

	/// Where the window is, and when it last moved.
	private var target: Placement?
	private var lastMove: TimeInterval = 0
	/// Where the window was when the tent was last turned to it.
	private var fitted: Placement?
	private var turn: Turn?

	private let session = ARKitSession()
	private let worldTracking = WorldTrackingProvider()
	/// Where the eye is taken to be when the head can't be tracked: the image's camera height,
	/// over the space's origin.
	private var defaultEye: SIMD3<Float> = [0, CinemaAnchors.seatedEyeHeight, 0]

	init() {
		frame.name = "WindowFrame"
		frame.isEnabled = false
	}

	/// Starts head tracking and makes the frame's shading. Head tracking needs no permission.
	func start() async {
		frameMaterial = await Self.makeFrameMaterial()
		guard WorldTrackingProvider.isSupported else {
			Logger.services.info("🎬 [Cinema] Head tracking isn't available; the front wall assumes a seated viewer")
			return
		}
		do {
			try await session.run([worldTracking])
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't start head tracking: \(error.localizedDescription, privacy: .public)")
		}
	}

	func stop() {
		session.stop()
	}

	/// Puts the environment's front wall image on the stage, or takes it away if there is none,
	/// and fits it to the window again from scratch.
	func setFrontWall(_ shape: CinemaAnchors.FrontWall?, imageName: String, eyeHeight: Float, on stage: Entity) async {
		wall?.removeFromParent()
		wall = nil
		wallShape = nil
		defaultEye = [0, eyeHeight, 0]
		fitted = nil
		turn = nil
		if let shape, shape.isValid, let url = cinemaEnvironmentFrontWallURL(named: imageName) {
			do {
				let texture = try await TextureResource(contentsOf: url, options: .init(semantic: .color))
				let wall = try Self.makeWall(shape, texture: texture)
				wall.isEnabled = false
				stage.addChild(wall)
				self.wall = wall
				wallShape = shape
			} catch {
				Logger.services.error("🎬 [Cinema] Couldn't make the front wall for \(imageName, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
		wallOpacity = 0
	}

	/// The window's corners in the scene: top left, top right, bottom left, bottom right.
	func setWindow(corners: [SIMD3<Float>], widthPoints: CGFloat) {
		guard let placement = Placement(corners: corners, widthPoints: Float(widthPoints)) else { return }
		if target == nil {
			snapFrame = true
		}
		if placement != target {
			target = placement
			lastMove = CACurrentMediaTime()
		}
	}

	func clearWindow() {
		target = nil
	}

	/// Moves everything a frame's worth. Called on every scene update.
	func update(deltaTime: TimeInterval, stage: Entity) {
		let now = CACurrentMediaTime()
		guard let target else {
			frame.isEnabled = false
			fadeWall(toward: 0, deltaTime: deltaTime)
			return
		}
		followWindow(target, deltaTime: deltaTime)
		if fitted.map({ !target.isNear($0) }) ?? true {
			if fitted == nil || Self.turnsLive {
				fit(stage, to: target, now: now, animated: false)
			} else if now - lastMove >= Self.settleTime {
				fit(stage, to: target, now: now, animated: true)
			}
		}
		advanceTurn(stage, now: now)
		let settled = fitted.map { target.isNear($0) } ?? false
		fadeWall(toward: settled && turn == nil ? 1 : 0, deltaTime: deltaTime)
	}

	// MARK: - Frame

	private func followWindow(_ target: Placement, deltaTime: TimeInterval) {
		if let frameMaterial, simd_length(target.size - frameSize) > 0.001 {
			frameSize = target.size
			frame.children.removeAll()
			do {
				let mesh = try Self.makeFrameMesh(size: target.size, cornerRadius: target.cornerRadius)
				frame.addChild(ModelEntity(mesh: mesh, materials: [frameMaterial]))
			} catch {
				Logger.services.error("🎬 [Cinema] Couldn't make the window frame: \(error.localizedDescription, privacy: .public)")
			}
		}
		// A light touch of smoothing, so a drag doesn't jitter the frame.
		let k = snapFrame ? 1 : Float(1 - exp(-deltaTime / 0.04))
		snapFrame = false
		frame.position = simd_mix(frame.position, target.center, SIMD3(repeating: k))
		frame.orientation = simd_slerp(frame.orientation, target.orientation, k)
		frame.isEnabled = true
	}

	// MARK: - Turning the tent

	/// Turns the stage so the painted front wall faces the window, centers it on the eye, and puts
	/// the wall image just behind the window, shrunk about the eye so it covers the painted wall.
	private func fit(_ stage: Entity, to target: Placement, now: TimeInterval, animated: Bool) {
		let eye = headPosition() ?? defaultEye
		var forward = -target.normal
		forward.y = 0
		guard simd_length(forward) > 0.01 else { return }
		forward = simd_normalize(forward)
		let depth = (target.corners.map { simd_dot($0 - eye, forward) }.max() ?? 0) + Self.wallGap
		guard depth > 0.3 else { return }
		let rotation = simd_quatf(angle: atan2(-forward.x, -forward.z), axis: [0, 1, 0])
		if let wall, let wallShape {
			wall.position = [0, 0, -depth]
			wall.scale = SIMD3(repeating: depth / wallShape.distance)
		}
		if animated {
			turn = Turn(fromPosition: stage.position, toPosition: eye, fromRotation: stage.orientation, toRotation: rotation, start: now)
		} else {
			turn = nil
			stage.position = eye
			stage.orientation = rotation
		}
		fitted = target
		Logger.services.debug("🎬 [Cinema] Front wall fitted \(depth, privacy: .public) m out, eye at \(eye.y, privacy: .public) m")
	}

	private func advanceTurn(_ stage: Entity, now: TimeInterval) {
		guard let turn else { return }
		let t = Float(min(max((now - turn.start) / Self.turnTime, 0), 1))
		let eased = t * t * (3 - 2 * t)
		stage.position = simd_mix(turn.fromPosition, turn.toPosition, SIMD3(repeating: eased))
		stage.orientation = simd_slerp(turn.fromRotation, turn.toRotation, eased)
		if t >= 1 {
			self.turn = nil
		}
	}

	private func fadeWall(toward opacity: Float, deltaTime: TimeInterval) {
		guard let wall else { return }
		// Out quickly when the window moves, back in a little slower.
		let rate: Float = opacity > wallOpacity ? 1 / 0.3 : 1 / 0.15
		let step = rate * Float(deltaTime)
		wallOpacity = opacity > wallOpacity ? min(opacity, wallOpacity + step) : max(opacity, wallOpacity - step)
		wall.isEnabled = wallOpacity > 0
		if wallOpacity >= 1 {
			wall.components.remove(OpacityComponent.self)
		} else {
			wall.components.set(OpacityComponent(opacity: wallOpacity))
		}
	}

	private func headPosition() -> SIMD3<Float>? {
		guard worldTracking.state == .running,
			  let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
			  device.isTracked else { return nil }
		let column = device.originFromAnchorTransform.columns.3
		return [column.x, column.y, column.z]
	}

	private struct Turn {
		var fromPosition: SIMD3<Float>
		var toPosition: SIMD3<Float>
		var fromRotation: simd_quatf
		var toRotation: simd_quatf
		var start: TimeInterval
	}

	/// The window in the scene, in meters, worked out from its corners. Corners, not
	/// `physicalMetrics`, because the system scales a window up with its distance.
	private struct Placement: Equatable {
		var corners: [SIMD3<Float>]
		var center: SIMD3<Float>
		var orientation: simd_quatf
		/// Toward the viewer.
		var normal: SIMD3<Float>
		var size: SIMD2<Float>
		var cornerRadius: Float

		init?(corners: [SIMD3<Float>], widthPoints: Float) {
			guard corners.count == 4, widthPoints > 0 else { return nil }
			let (topLeft, topRight, bottomLeft) = (corners[0], corners[1], corners[2])
			let across = topRight - topLeft, upward = topLeft - bottomLeft
			let width = simd_length(across), height = simd_length(upward)
			guard width > 0.01, height > 0.01 else { return nil }
			let right = across / width, up = upward / height
			let normal = simd_normalize(simd_cross(right, up))
			self.corners = corners
			center = corners.reduce(.zero, +) / 4
			orientation = simd_quatf(simd_float3x3(columns: (right, up, normal)))
			self.normal = normal
			size = [width, height]
			cornerRadius = CinemaWindowMount.windowCornerRadius * width / widthPoints
		}

		/// Close enough that the tent doesn't need turning again.
		func isNear(_ other: Placement) -> Bool {
			simd_distance(center, other.center) < 0.01
				&& simd_dot(normal, other.normal) > cos(Float.pi / 360)
				&& simd_length(size - other.size) < 0.005
		}
	}

	// MARK: - Meshes

	/// The wall's outline as a flat mesh, `distance` in front of the origin, facing it, with the
	/// image stretched over the outline's bounds.
	private static func makeWall(_ shape: CinemaAnchors.FrontWall, texture: TextureResource) throws -> ModelEntity {
		let left = shape.bounds[0], bottom = shape.bounds[1], right = shape.bounds[2], top = shape.bounds[3]
		var descriptor = MeshDescriptor(name: "FrontWall")
		descriptor.positions = MeshBuffers.Positions(shape.outline.map { [$0[0], $0[1], 0] })
		descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(shape.outline.map {
			[($0[0] - left) / (right - left), ($0[1] - bottom) / (top - bottom)]
		})
		// The outline is convex (a wall with a gable on top), so a fan covers it.
		descriptor.primitives = .triangles((1..<UInt32(shape.outline.count - 1)).flatMap { [0, $0, $0 + 1] })
		var material = UnlitMaterial()
		material.color = .init(tint: .white, texture: .init(texture))
		let wall = ModelEntity(mesh: try MeshResource.generate(from: [descriptor]), materials: [material])
		wall.name = "FrontWall"
		// The mesh is at the image's own distance; `fit` moves it in and shrinks it.
		wall.position = [0, 0, -shape.distance]
		return wall
	}

	/// Stops across the frame, out from the window's edge in meters, and the gray at each (sRGB,
	/// 0 to 1). It starts under the window, so no gap shows from the side, darkest where the window
	/// meets it, and catches a little light along its outer edge.
	private static let frameStops: [(offset: Float, gray: Float)] = [
		(-0.008, 0.0), (0.0, 0.008), (0.010, 0.04), (0.030, 0.07), (0.036, 0.12), (frameWidth, 0.06)
	]

	/// A flat rounded frame round a window of `size`, filled in behind the window, just behind
	/// the window's plane. Its inner corners follow the window's.
	private static func makeFrameMesh(size: SIMD2<Float>, cornerRadius: Float) throws -> MeshResource {
		let halfWidth = size.x / 2, halfHeight = size.y / 2
		let radius = min(cornerRadius, halfWidth, halfHeight)
		let segments = 8
		let perRing = 4 * (segments + 1)
		let first = frameStops.first?.offset ?? 0, last = frameStops.last?.offset ?? 1
		var positions: [SIMD3<Float>] = []
		var coordinates: [SIMD2<Float>] = []
		for stop in frameStops {
			let u = (stop.offset - first) / (last - first)
			let ringRadius = max(radius + stop.offset, 0)
			for corner in 0..<4 {
				let x = corner == 0 || corner == 3 ? halfWidth - radius : radius - halfWidth
				let y = corner < 2 ? halfHeight - radius : radius - halfHeight
				for step in 0...segments {
					let angle = (Float(corner) + Float(step) / Float(segments)) * .pi / 2
					positions.append([x + ringRadius * cos(angle), y + ringRadius * sin(angle), -frameGap])
					coordinates.append([u, 0.5])
				}
			}
		}
		var indices: [UInt32] = []
		for ring in 0..<(frameStops.count - 1) {
			for i in 0..<perRing {
				let a = UInt32(ring * perRing + i), a1 = UInt32(ring * perRing + (i + 1) % perRing)
				let b = a + UInt32(perRing), b1 = a1 + UInt32(perRing)
				indices += [a, b, b1, a, b1, a1]
			}
		}
		// The backing behind the window.
		let center = UInt32(positions.count)
		positions.append([0, 0, -frameGap])
		coordinates.append([0, 0.5])
		for i in 0..<perRing {
			indices += [center, UInt32(i), UInt32((i + 1) % perRing)]
		}
		var descriptor = MeshDescriptor(name: "WindowFrame")
		descriptor.positions = MeshBuffers.Positions(positions)
		descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
		descriptor.primitives = .triangles(indices)
		return try MeshResource.generate(from: [descriptor])
	}

	/// The frame's shading as a strip of grays, read across the frame by the mesh's U.
	private static func makeFrameMaterial() async -> UnlitMaterial {
		var material = UnlitMaterial(color: UIColor(white: 0.03, alpha: 1))
		let width = 64
		let first = frameStops.first?.offset ?? 0, last = frameStops.last?.offset ?? 1
		var pixels = [UInt8](repeating: 255, count: width * 4)
		for x in 0..<width {
			let offset = first + (last - first) * Float(x) / Float(width - 1)
			let next = frameStops.firstIndex { $0.offset >= offset } ?? frameStops.count - 1
			let previous = max(next - 1, 0)
			let (a, b) = (frameStops[previous], frameStops[next])
			let t = b.offset > a.offset ? (offset - a.offset) / (b.offset - a.offset) : 0
			let gray = UInt8(min(max(a.gray + (b.gray - a.gray) * t, 0), 1) * 255)
			pixels[x * 4] = gray
			pixels[x * 4 + 1] = gray
			pixels[x * 4 + 2] = gray
		}
		guard let provider = CGDataProvider(data: Data(pixels) as CFData),
			  let image = CGImage(
				width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
				space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
				provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
			  ) else { return material }
		do {
			let texture = try await TextureResource(image: image, options: .init(semantic: .color))
			material.color = .init(tint: .white, texture: .init(texture))
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make the window frame's shading: \(error.localizedDescription, privacy: .public)")
		}
		return material
	}
}
#endif
