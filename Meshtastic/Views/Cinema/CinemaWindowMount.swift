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
import Spatial
import UIKit

/// Sets the main window into the tent's front wall. Nothing can pin a window in place, so the wall
/// comes to the window instead: a black frame sits just behind the window and follows it, and the
/// front wall, as its own flat image, sits just behind that at the window's depth. The painted
/// tent turns so its front wall faces the window. While the window is moving the wall fades out,
/// and once it has been still for a moment the tent turns to it and the wall fades back in. The
/// wall stops short of the Spatial Map volume, so it never hides it.
///
/// The wall image only lines up with the painting behind it when seen from the point it is shrunk
/// about. At 2 m against a painting 50 m out, a head 10 cm away from that point puts the wall's
/// edges about 3° off the painted ones, and the tent shows two sets of roof lines. So the tent
/// follows the head as it moves, and only turns with the window. The wall stays upright and square
/// to the tent whatever the window's tilt; only the frame tilts with the window.
@MainActor
final class CinemaWindowMount {
	/// Turns the tent with the window while it is being dragged, instead of once it has settled.
	/// For comparing the two on a device.
	static let turnsLive = false
	/// Moves the tent with the head, so the wall stays lined up with the painting. Off, the tent
	/// stays where the head was when it was last turned. For comparing the two on a device.
	static let followsHead = true

	/// The frame round the window and the dark backing behind it. Goes in the scene's world, not
	/// the stage, since it follows the window rather than the painting.
	let frame = Entity()

	/// How far behind the window the frame sits, and how far behind the frame's farthest point the
	/// wall sits, in meters.
	private static let frameGap: Float = 0.01
	private static let wallGap: Float = 0.02
	/// How wide the frame is round the window, in meters.
	private static let frameWidth: Float = 0.04
	/// A visionOS window's corner radius, in the window's points.
	private nonisolated static let windowCornerRadius: Float = 46
	/// How long the window must be still before the tent turns to it.
	private static let settleTime: TimeInterval = 0.5
	/// The shortest the turn takes, and the fastest the tent turns: 45° a second.
	private static let turnTime: TimeInterval = 0.4
	private static let turnSpeed: Float = .pi / 4
	/// How far the wall stops short of the Spatial Map volume, in meters at the wall image's own
	/// distance: about 1°.
	private static let volumeMargin: Float = 0.05
	/// How far the trimmed edge can drift as the head moves before the wall's mesh is made again,
	/// in the same meters.
	private static let trimTolerance: Float = 0.02

	private var wall: ModelEntity?
	private var wallShape: CinemaAnchors.FrontWall?
	/// The part of the wall that is drawn, across, in the wall image's meters. Nil for all of it.
	private var wallKeeps: ClosedRange<Float>?
	private var wallOpacity: Float = 0
	private var frameMaterial: UnlitMaterial?
	/// The window size the frame's mesh was made for. In between it is scaled.
	private var frameMeshSize: SIMD2<Float>?
	private var snapFrame = true

	/// Converts `.immersiveSpace` points to scene meters.
	private var spaceToScene: simd_float4x4?
	/// The last poses read, so each is only worked out once.
	private var windowPose: CinemaWindowPose?
	private var volumePose: CinemaVolumePose?
	/// Where the window and the volume are, in the scene.
	private var target: Placement?
	private var volume: [SIMD3<Float>]?
	/// Where they were when they last moved, and when.
	private var stillWindow: Placement?
	private var stillVolume: [SIMD3<Float>]?
	private var lastMove: TimeInterval = 0
	/// The last time the tent was turned to the window.
	private var fit: Fit?
	private var turn: Turn?
	private var loggedSkippedFit = false
	/// The last registration error logged, in degrees, and when.
	private var loggedRegistration: (degrees: Float, time: TimeInterval) = (0, 0)

	private let session = ARKitSession()
	private let worldTracking = WorldTrackingProvider()
	private var isStopped = false
	/// Where the eye is taken to be when the head can't be tracked: the image's camera height,
	/// over the space's origin.
	private var defaultEye: SIMD3<Float> = [0, CinemaAnchors.seatedEyeHeight, 0]

	init() {
		frame.name = "WindowFrame"
		frame.isEnabled = false
	}

	/// Whether the tent has been turned to the window yet.
	var isFitted: Bool {
		fit != nil
	}

	/// Starts head tracking and makes the frame's shading. Head tracking needs no permission.
	func start() async {
		let material = await Self.makeFrameMaterial()
		guard !isStopped else { return }
		frameMaterial = material
		guard WorldTrackingProvider.isSupported else {
			Logger.services.info("🎬 [Cinema] Head tracking isn't available; the front wall assumes a seated viewer")
			return
		}
		do {
			try await session.run([worldTracking])
			// The cinema may have closed while tracking started.
			if isStopped {
				session.stop()
			}
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't start head tracking: \(error.localizedDescription, privacy: .public)")
		}
	}

	func stop() {
		isStopped = true
		session.stop()
	}

	/// How `.immersiveSpace` points map to the scene: where the origin and a point a thousand points
	/// along each axis land. Only a view's RealityView content can convert, so it passes these in.
	func setSpaceConversion(origin: SIMD3<Float>, x: SIMD3<Float>, y: SIMD3<Float>, z: SIMD3<Float>) {
		let conversion = simd_float4x4(columns: (
			SIMD4((x - origin) / 1000, 0), SIMD4((y - origin) / 1000, 0), SIMD4((z - origin) / 1000, 0), SIMD4(origin, 1)
		))
		guard conversion != spaceToScene else { return }
		spaceToScene = conversion
		// Work the poses out again with it.
		windowPose = nil
		volumePose = nil
	}

	/// Puts the environment's front wall image on the stage, or takes it away if there is none.
	/// The tent stays where it is; the next frame puts the new wall where the old one was.
	func setFrontWall(_ shape: CinemaAnchors.FrontWall?, imageName: String, eyeHeight: Float, on stage: Entity) async {
		wall?.removeFromParent()
		wall = nil
		wallShape = nil
		wallKeeps = nil
		defaultEye = [0, eyeHeight, 0]
		if let shape, shape.isValid, let url = cinemaEnvironmentFrontWallURL(named: imageName) {
			do {
				let texture = try await TextureResource(contentsOf: url, options: .init(semantic: .color))
				var material = UnlitMaterial()
				material.color = .init(tint: .white, texture: .init(texture))
				let wall = ModelEntity(mesh: try Self.makeWallMesh(shape, keeping: nil), materials: [material])
				wall.name = "FrontWall"
				// At the image's own distance until it is fitted.
				wall.position = [0, 0, -shape.distance]
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

	/// Moves everything a frame's worth. Called on every scene update with the main window's and
	/// the Spatial Map volume's poses, read straight from the tracker so a drag redraws no views.
	func update(deltaTime: TimeInterval, stage: Entity, window: CinemaWindowPose?, volume: CinemaVolumePose?) {
		let now = CACurrentMediaTime()
		take(window: window, volume: volume, now: now)
		guard let target else {
			frame.isEnabled = false
			fadeWall(toward: 0, deltaTime: deltaTime)
			return
		}
		followWindow(target, now: now, deltaTime: deltaTime)
		let head = headPosition()
		let moved = fit.map { !isFitted(target, $0) } ?? true
		if moved || (fit?.knewHead == false && head != nil) {
			if fit == nil || Self.turnsLive {
				fit(stage, to: target, head: head, now: now, animated: false)
			} else if now - lastMove >= Self.settleTime {
				fit(stage, to: target, head: head, now: now, animated: true)
			}
		}
		if let fit {
			let eye = Self.followsHead ? head ?? fit.eye : fit.eye
			advanceTurn(stage, eye: eye, now: now)
			placeWall(target, eye: eye, rotation: fit.rotation)
			if let head {
				checkRegistration(stage, head: head, now: now)
			}
		}
		let settled = fit.map { isFitted(target, $0) } ?? false
		fadeWall(toward: settled && turn == nil ? 1 : 0, deltaTime: deltaTime)
	}

	/// Reads new poses into scene coordinates and notes when either really moved, so jitter in the
	/// reports can't keep putting the turn off.
	private func take(window: CinemaWindowPose?, volume: CinemaVolumePose?, now: TimeInterval) {
		guard let spaceToScene else { return }
		if window != windowPose {
			windowPose = window
			if let window, let placement = Placement(corners: window.corners.map { Self.convert($0, spaceToScene) }, widthPoints: Float(window.size.width)) {
				if target == nil {
					snapFrame = true
				}
				target = placement
				if !(stillWindow.map { placement.isNear($0, Placement.still) } ?? false) {
					stillWindow = placement
					lastMove = now
				}
			} else {
				target = nil
				stillWindow = nil
			}
		}
		if volume != volumePose {
			volumePose = volume
			let corners = volume.map { $0.corners.map { Self.convert($0, spaceToScene) } }
			self.volume = corners
			if !Self.isNear(corners, stillVolume, within: Placement.still.distance) {
				stillVolume = corners
				lastMove = now
			}
		}
	}

	private func isFitted(_ target: Placement, _ fit: Fit) -> Bool {
		target.isNear(fit.window, Placement.fitted) && Self.isNear(volume, fit.volume, within: Placement.fitted.distance)
	}

	private static func isNear(_ a: [SIMD3<Float>]?, _ b: [SIMD3<Float>]?, within distance: Float) -> Bool {
		guard let a, let b else { return a == nil && b == nil }
		return a.count == b.count && zip(a, b).allSatisfy { simd_distance($0, $1) < distance }
	}

	private static func convert(_ point: Point3D, _ conversion: simd_float4x4) -> SIMD3<Float> {
		let p = conversion * SIMD4(Float(point.x), Float(point.y), Float(point.z), 1)
		return [p.x, p.y, p.z]
	}

	// MARK: - Frame

	/// The frame is built for one window size and scaled as the window moves in and out, which
	/// changes its size every frame. It is built again when the shape changes, or once the window
	/// has settled at a new size, so its edge goes back to its own width.
	private func followWindow(_ target: Placement, now: TimeInterval, deltaTime: TimeInterval) {
		if let frameMaterial {
			let aspect = target.size.x / target.size.y
			let rebuild = frameMeshSize.map { built in
				abs(aspect - built.x / built.y) > 0.005 * aspect
					|| (now - lastMove >= Self.settleTime && abs(target.size.x / built.x - 1) > 0.02)
			} ?? true
			if rebuild {
				frame.children.removeAll()
				do {
					let mesh = try Self.makeFrameMesh(size: target.size, cornerRadius: target.cornerRadius)
					frame.addChild(ModelEntity(mesh: mesh, materials: [frameMaterial]))
					frameMeshSize = target.size
				} catch {
					Logger.services.error("🎬 [Cinema] Couldn't make the window frame: \(error.localizedDescription, privacy: .public)")
				}
			}
		}
		let scale = frameScale(for: target)
		frame.scale = [scale, scale, 1]
		// A light touch of smoothing, so a drag doesn't jitter the frame.
		let k = snapFrame ? 1 : Float(1 - exp(-deltaTime / 0.04))
		snapFrame = false
		frame.position = simd_mix(frame.position, target.center, SIMD3(repeating: k))
		frame.orientation = simd_slerp(frame.orientation, target.orientation, k)
		frame.isEnabled = true
	}

	private func frameScale(for target: Placement) -> Float {
		frameMeshSize.map { target.size.x / $0.x } ?? 1
	}

	/// The frame's outer corners, in its own plane just behind the window. Its corners are rounded,
	/// so these are a little outside it.
	private func frameCorners(_ target: Placement) -> [SIMD3<Float>] {
		let width = Self.frameWidth * frameScale(for: target)
		let back = -target.normal * Self.frameGap
		let signs: [SIMD2<Float>] = [[-1, 1], [1, 1], [-1, -1], [1, -1]]
		return zip(target.corners, signs).map { corner, sign in
			corner + target.right * (sign.x * width) + target.up * (sign.y * width) + back
		}
	}

	/// How far out the wall must be, along `forward` from `eye`, to sit behind the whole frame.
	/// Measured from the frame's corners, so a window tilted up or down to face the viewer doesn't
	/// push the frame's far edge through the wall. Worked out every frame, so no move of the window
	/// or the head can take the frame through it.
	private func wallDepth(for target: Placement, eye: SIMD3<Float>, forward: SIMD3<Float>) -> Float {
		(frameCorners(target).map { simd_dot($0 - eye, forward) }.max() ?? 0) + Self.wallGap
	}

	// MARK: - Turning the tent

	/// Turns the stage so the painted front wall faces the window. Only its heading follows the
	/// window; the tent stays upright however the window is tilted.
	private func fit(_ stage: Entity, to target: Placement, head: SIMD3<Float>?, now: TimeInterval, animated: Bool) {
		let eye = head ?? defaultEye
		var forward = -target.normal
		forward.y = 0
		guard simd_length(forward) > 0.01 else {
			logSkippedFit("the window faces straight up or down")
			return
		}
		forward = simd_normalize(forward)
		let rotation = simd_quatf(angle: atan2(-forward.x, -forward.z), axis: [0, 1, 0])
		let depth = wallDepth(for: target, eye: eye, forward: forward)
		guard depth > 0.3 else {
			logSkippedFit("the window is too close")
			return
		}
		if animated {
			let angle = 2 * acos(min(abs(simd_dot(stage.orientation.vector, rotation.vector)), 1))
			let duration = max(Self.turnTime, TimeInterval(angle / Self.turnSpeed))
			turn = Turn(fromPosition: stage.position, fromRotation: stage.orientation, toRotation: rotation, start: now, duration: duration)
		} else {
			turn = nil
			stage.position = eye
			stage.orientation = rotation
		}
		fit = Fit(window: target, volume: volume, eye: eye, rotation: rotation, knewHead: head != nil)
		loggedSkippedFit = false
		Logger.services.debug("🎬 [Cinema] Tent turned to the window \(depth, privacy: .public) m out, eye at \(eye, privacy: .public)")
	}

	private func logSkippedFit(_ reason: String) {
		guard !loggedSkippedFit else { return }
		loggedSkippedFit = true
		Logger.services.info("🎬 [Cinema] Not fitting the front wall: \(reason, privacy: .public)")
	}

	/// Keeps the wall off the Spatial Map volume. If the volume reaches back past the wall and its
	/// middle is to one side of the window's, the wall stops short of it on that side, even where
	/// that cuts behind the window, which hides the wall there anyway. Past the cut the painted wall
	/// shows, which looks the same from the seat. If the volume is behind the middle of the window,
	/// the wall goes back behind it.
	private func clearOfVolume(_ target: Placement, eye: SIMD3<Float>, rotation: simd_quatf, depth: Float) -> (depth: Float, keeps: ClosedRange<Float>?) {
		guard let volume, let wallShape else { return (depth, nil) }
		let toStage = rotation.inverse
		let local = volume.map { toStage.act($0 - eye) }
		let far = local.map { -$0.z }.max() ?? 0
		guard far > depth - Self.wallGap else { return (depth, nil) }
		// Across the wall image, as seen from the eye.
		func across(_ points: [SIMD3<Float>]) -> ClosedRange<Float>? {
			let xs = points.compactMap { -$0.z > 0.05 ? $0.x * wallShape.distance / -$0.z : nil }
			guard xs.count == points.count, let low = xs.min(), let high = xs.max() else { return nil }
			return low...high
		}
		if let window = across(frameCorners(target).map { toStage.act($0 - eye) }), let volume = across(local) {
			let middle = (window.lowerBound + window.upperBound) / 2
			if volume.lowerBound > middle {
				return (depth, -Float.infinity...(volume.lowerBound - Self.volumeMargin))
			}
			if volume.upperBound < middle {
				return (depth, (volume.upperBound + Self.volumeMargin)...Float.infinity)
			}
		}
		return (max(depth, far + Self.wallGap), nil)
	}

	/// Puts the wall just behind the frame as seen from `eye`, and shrunk about it, so from there it
	/// covers the painted wall exactly. Trimmed or pushed back for the Spatial Map volume.
	private func placeWall(_ target: Placement, eye: SIMD3<Float>, rotation: simd_quatf) {
		guard let wall, let wallShape else { return }
		let depth = wallDepth(for: target, eye: eye, forward: rotation.act([0, 0, -1]))
		let clear = clearOfVolume(target, eye: eye, rotation: rotation, depth: depth)
		if !Self.isNear(clear.keeps, wallKeeps) {
			do {
				wall.model?.mesh = try Self.makeWallMesh(wallShape, keeping: clear.keeps)
				wallKeeps = clear.keeps
			} catch {
				Logger.services.error("🎬 [Cinema] Couldn't trim the front wall: \(error.localizedDescription, privacy: .public)")
			}
		}
		wall.position = [0, 0, -clear.depth]
		wall.scale = SIMD3(repeating: clear.depth / wallShape.distance)
	}

	private static func isNear(_ a: ClosedRange<Float>?, _ b: ClosedRange<Float>?) -> Bool {
		guard let a, let b else { return a == nil && b == nil }
		func near(_ x: Float, _ y: Float) -> Bool {
			x == y || abs(x - y) < trimTolerance
		}
		return near(a.lowerBound, b.lowerBound) && near(a.upperBound, b.upperBound)
	}

	/// Turns the stage toward the last fit's heading, and keeps it on the eye.
	private func advanceTurn(_ stage: Entity, eye: SIMD3<Float>, now: TimeInterval) {
		guard let turn else {
			stage.position = eye
			return
		}
		let t = Float(min(max((now - turn.start) / turn.duration, 0), 1))
		let eased = t * t * (3 - 2 * t)
		stage.position = simd_mix(turn.fromPosition, eye, SIMD3(repeating: eased))
		stage.orientation = simd_slerp(turn.fromRotation, turn.toRotation, eased)
		if t >= 1 {
			self.turn = nil
		}
	}

	/// Logs how far the wall's corners sit from the painted wall's, in degrees as seen from the head,
	/// when that changes. Zero while the tent follows the head; the seam each eye sees, about 1°
	/// either way at 2 m, isn't counted.
	private func checkRegistration(_ stage: Entity, head: SIMD3<Float>, now: TimeInterval) {
		guard let wall, let wallShape, wall.isEnabled else { return }
		var worst: Float = 0
		for point in wallShape.outline {
			let onWall = wall.convert(position: [point[0], point[1], 0], to: nil)
			let painted = stage.convert(direction: simd_normalize(SIMD3(point[0], point[1], -wallShape.distance)), to: nil)
			let painting = stage.position(relativeTo: nil) + painted * CinemaBackdrop.radius
			let cosine = simd_dot(simd_normalize(onWall - head), simd_normalize(painting - head))
			worst = max(worst, acos(min(cosine, 1)) * 180 / .pi)
		}
		let changed = abs(worst - loggedRegistration.degrees) > 0.25
		guard changed, now - loggedRegistration.time > 1 else { return }
		loggedRegistration = (worst, now)
		let offset = head - stage.position(relativeTo: nil)
		Logger.services.debug("🎬 [Cinema] Front wall is \(worst, format: .fixed(precision: 2), privacy: .public)° off the painting at its worst corner; head is \(simd_length(offset), format: .fixed(precision: 3), privacy: .public) m from the tent's center")
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

	/// What the tent was last turned to, and where that put the wall.
	private struct Fit {
		var window: Placement
		var volume: [SIMD3<Float>]?
		/// Where the head was. The tent stays there when it doesn't follow the head.
		var eye: SIMD3<Float>
		var rotation: simd_quatf
		/// Whether the eye came from head tracking. Head tracking starts after the window is first
		/// placed, so the first fit usually guesses and is redone once it can.
		var knewHead: Bool
	}

	private struct Turn {
		var fromPosition: SIMD3<Float>
		var fromRotation: simd_quatf
		var toRotation: simd_quatf
		var start: TimeInterval
		var duration: TimeInterval
	}

	/// The window in the scene, in meters, worked out from its corners. Corners, not
	/// `physicalMetrics`, because the system scales a window up with its distance.
	private struct Placement {
		var corners: [SIMD3<Float>]
		var center: SIMD3<Float>
		var orientation: simd_quatf
		var right: SIMD3<Float>
		var up: SIMD3<Float>
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
			self.right = right
			self.up = up
			self.normal = normal
			size = [width, height]
			cornerRadius = CinemaWindowMount.windowCornerRadius * width / widthPoints
		}

		struct Tolerance {
			var distance: Float
			var angle: Float
		}

		/// Close enough that the tent doesn't need turning again. The wall's depth is kept apart.
		static let fitted = Tolerance(distance: 0.01, angle: .pi / 360)
		/// Close enough to count as not having moved, allowing for jitter in the reports.
		static let still = Tolerance(distance: 0.002, angle: .pi / 1800)

		func isNear(_ other: Placement, _ tolerance: Tolerance) -> Bool {
			simd_distance(center, other.center) < tolerance.distance
				&& simd_dot(normal, other.normal) > cos(tolerance.angle)
				&& simd_length(size - other.size) < tolerance.distance
		}
	}

}

// MARK: - Meshes

@MainActor
extension CinemaWindowMount {
	/// The wall's outline as a flat mesh, facing the origin, with the image stretched over the
	/// outline's bounds. `keeping` trims it to a range across, for the Spatial Map volume.
	private static func makeWallMesh(_ shape: CinemaAnchors.FrontWall, keeping: ClosedRange<Float>?) throws -> MeshResource {
		let left = shape.bounds[0], bottom = shape.bounds[1], right = shape.bounds[2], top = shape.bounds[3]
		var outline = shape.outline.map { SIMD2($0[0], $0[1]) }
		if let keeping {
			outline = clip(outline, keepingAbove: keeping.lowerBound, sign: 1)
			outline = clip(outline, keepingAbove: -keeping.upperBound, sign: -1)
		}
		guard outline.count >= 3 else {
			// Nothing left: a sliver at the edge, so there is still a mesh.
			return try makeWallMesh(shape, keeping: left...(left + 0.001))
		}
		var descriptor = MeshDescriptor(name: "FrontWall")
		descriptor.positions = MeshBuffers.Positions(outline.map { [$0.x, $0.y, 0] })
		descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(outline.map {
			[($0.x - left) / (right - left), ($0.y - bottom) / (top - bottom)]
		})
		// The outline is convex (a wall with a gable on top, maybe cut straight down one side), so a
		// fan covers it.
		descriptor.primitives = .triangles((1..<UInt32(outline.count - 1)).flatMap { [0, $0, $0 + 1] })
		return try MeshResource.generate(from: [descriptor])
	}

	/// Cuts a convex outline down to the part where `sign * x >= limit`.
	private static func clip(_ outline: [SIMD2<Float>], keepingAbove limit: Float, sign: Float) -> [SIMD2<Float>] {
		guard limit.isFinite else { return outline }
		var kept: [SIMD2<Float>] = []
		for (i, a) in outline.enumerated() {
			let b = outline[(i + 1) % outline.count]
			let da = sign * a.x - limit, db = sign * b.x - limit
			if da >= 0 {
				kept.append(a)
			}
			if (da >= 0) != (db >= 0) {
				kept.append(a + (b - a) * (da / (da - db)))
			}
		}
		return kept
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
