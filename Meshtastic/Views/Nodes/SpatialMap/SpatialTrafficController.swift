//
//  SpatialTrafficController.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import Foundation
import RealityKit
import UIKit

/// The moving parts of the volume, stepped once per rendered frame: packet pulses arcing from
/// the sender to the connected radio, rings rippling from a tower that was heard, the activity
/// halo under each node, and the flyover comet.
@MainActor
final class SpatialTrafficController {
	static let poolSize = 24
	/// Enough rings for six towers rippling at once.
	static let ringPoolSize = SpatialSignalRings.count * 6

	private struct Pulse {
		let entity: ModelEntity
		let from: SIMD3<Float>
		let to: SIMD3<Float>
		let duration: TimeInterval
		var elapsed: TimeInterval = 0
	}

	private struct RingBurst {
		let rings: [ModelEntity]
		let origin: SIMD3<Float>
		var elapsed: TimeInterval = 0
	}

	private let scene: SpatialSceneController
	private static let pulseMesh = MeshResource.generateSphere(radius: 0.007)
	private var idle: [ModelEntity] = []
	private var active: [Pulse] = []
	private var limiter = PulseRateLimiter()
	private var idleRings: [ModelEntity] = []
	private var bursts: [RingBurst] = []
	private var ringLimiter = SpatialSignalRings.limiter()
	private var boosts: [Int64: (start: TimeInterval, initial: Float)] = [:]
	private var clock: TimeInterval = 0
	private var flyover: SpatialFlyover?
	private var flownRoute: SpatialRouteSnapshot?
	private var flownRevision: Int?
	private let comet: SpatialFlyoverComet

	var showPulses = true
	var showGlow = true { didSet { if !showGlow { clearHalos() } } }
	var isHighTraffic = false
	var preset: ModemPresets = .longFast
	var connectedNodeNum: Int64?

	init(scene: SpatialSceneController) {
		self.scene = scene
		comet = SpatialFlyoverComet(parent: scene.trafficContainer)
		for _ in 0..<Self.poolSize {
			let entity = ModelEntity(mesh: Self.pulseMesh, materials: [UnlitMaterial(color: .white)])
			entity.isEnabled = false
			scene.trafficContainer.addChild(entity)
			idle.append(entity)
		}
		if let ringMesh = SpatialTowerParts.ringMesh {
			for _ in 0..<Self.ringPoolSize {
				let ring = ModelEntity(mesh: ringMesh, materials: [UnlitMaterial(color: .white)])
				ring.isEnabled = false
				ring.components.set(OpacityComponent(opacity: 0))
				scene.trafficContainer.addChild(ring)
				idleRings.append(ring)
			}
		}
	}

	// MARK: Packets

	func handle(_ event: MeshPacketEvent) {
		if showGlow { boosts[event.from] = (clock, 1) }
		if showPulses, !event.viaMqtt, event.from != connectedNodeNum { ripple(from: event.from) }
		guard showPulses, !event.viaMqtt, let connectedNodeNum, event.from != connectedNodeNum,
			  limiter.admit(sender: event.from, now: clock, highTraffic: isHighTraffic),
			  let from = scene.pinPosition(event.from), let to = scene.pinPosition(connectedNodeNum),
			  let entity = idle.popLast() else { return }
		let distance = simd_distance(from, to)
		let duration = min(max(TimeInterval(distance / 0.5), 0.4), 1.6)
		entity.model?.materials = [UnlitMaterial(color: UIColor(getSnrColor(snr: event.rxSnr, preset: preset)))]
		let size: Float = event.hopsTraveled.map { $0 > 0 ? 0.8 : 1.1 } ?? 1
		entity.scale = SIMD3(repeating: size * scene.counterScale)
		entity.position = from
		entity.isEnabled = true
		active.append(Pulse(entity: entity, from: from, to: to, duration: duration))
	}

	/// Sends rings out from a tower's antenna, when the sender is a tower and the pool and rate
	/// limit allow.
	private func ripple(from nodeNum: Int64) {
		guard idleRings.count >= SpatialSignalRings.count, let origin = scene.antennaPosition(nodeNum),
			  ringLimiter.admit(sender: nodeNum, now: clock, highTraffic: isHighTraffic) else { return }
		let material = UnlitMaterial(color: SpatialSceneController.nodeColor(nodeNum).lighter(componentDelta: 0.35))
		let rings = (0..<SpatialSignalRings.count).compactMap { _ in idleRings.popLast() }
		for ring in rings { ring.model?.materials = [material] }
		bursts.append(RingBurst(rings: rings, origin: origin))
	}

	// MARK: Flyover

	/// Flies the comet along the route; the scene draws the route itself. The legs follow the
	/// ground and the comet is lifted per frame, so it stays just above the pins at any zoom.
	func startFlyover(_ route: SpatialRouteSnapshot, speed: Double = 1) {
		guard let placement = scene.placement else { return }
		var flyover = SpatialFlyover(legs: Self.legs(route, on: placement))
		flyover.speedMultiplier = speed
		guard !flyover.legs.isEmpty else { return }
		self.flyover = flyover
		flownRoute = route
		flownRevision = placement.revision
	}

	private static func legs(_ route: SpatialRouteSnapshot, on placement: SpatialPlacement) -> [[SIMD3<Float>]] {
		[route.forward, route.back].map { path in
			path.map { SpatialZoom.clampToDisk(placement.surface($0.coordinate), diskRadius: placement.diskRadius) }
		}
	}

	/// Stops the comet. The route itself stays drawn until it is cleared.
	func stopFlyover() {
		flyover = nil
		flownRoute = nil
		comet.hide()
	}

	// MARK: Per frame

	func step(deltaTime dt: TimeInterval) {
		clock += dt
		if !active.isEmpty {
			var still: [Pulse] = []
			for var pulse in active {
				pulse.elapsed += dt
				let t = Float(min(pulse.elapsed / pulse.duration, 1))
				pulse.entity.position = Self.arc(from: pulse.from, to: pulse.to, t: t)
				if t >= 1 {
					pulse.entity.isEnabled = false
					idle.append(pulse.entity)
					if let connectedNodeNum, showGlow { boosts[connectedNodeNum] = (clock, 0.7) }
				} else {
					still.append(pulse)
				}
			}
			active = still
		}
		if !bursts.isEmpty { stepRings(deltaTime: dt) }
		if !boosts.isEmpty {
			for (num, boost) in boosts {
				let value = NodeActivityGlow.boost(startedAt: boost.start, now: clock, initial: boost.initial)
				let base = scene.baseGlow(num)
				scene.setHalo(num, opacity: NodeActivityGlow.opacity(base: base, boost: value), scale: NodeActivityGlow.scale(boost: value))
				if value < NodeActivityGlow.boostFloor { boosts[num] = nil }
			}
		}
		if var flyover {
			// The map zoomed or its terrain arrived mid-flight: carry on over the new positions.
			if let placement = scene.placement, placement.revision != flownRevision, let flownRoute {
				flownRevision = placement.revision
				guard let moved = flyover.moved(to: Self.legs(flownRoute, on: placement)) else { return stopFlyover() }
				flyover = moved
			}
			if let position = flyover.advance(by: dt) {
				self.flyover = flyover
				// Reduce Motion keeps the head and drops the tail.
				comet.update(flyover, position: position, lift: SpatialSceneController.flyHeight * scene.counterScale, counterScale: scene.counterScale, showTail: !UIAccessibility.isReduceMotionEnabled)
			} else {
				stopFlyover()
			}
		}
	}

	private func stepRings(deltaTime dt: TimeInterval) {
		var still: [RingBurst] = []
		for var burst in bursts {
			burst.elapsed += dt
			for (index, ring) in burst.rings.enumerated() {
				guard let state = SpatialSignalRings.ring(index, elapsed: burst.elapsed) else {
					ring.isEnabled = false
					continue
				}
				let radius = state.radius * scene.counterScale
				ring.position = burst.origin
				ring.scale = [radius, scene.counterScale, radius]
				ring.components.set(OpacityComponent(opacity: state.opacity))
				ring.isEnabled = true
			}
			if burst.elapsed >= SpatialSignalRings.burstDuration {
				for ring in burst.rings { ring.isEnabled = false }
				idleRings += burst.rings
			} else {
				still.append(burst)
			}
		}
		bursts = still
	}

	/// Sets every halo to its recency level; called after the node list refreshes.
	func applyBaseGlow() {
		guard showGlow else { return }
		scene.forEachPin { num in
			if boosts[num] == nil {
				scene.setHalo(num, opacity: scene.baseGlow(num), scale: 1)
			}
		}
	}

	private func clearHalos() {
		boosts.removeAll()
		scene.forEachPin { scene.setHalo($0, opacity: 0, scale: 1) }
	}

	/// A quadratic arc whose apex rises with the distance flown.
	static func arc(from a: SIMD3<Float>, to b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
		let apex = 0.04 + 0.25 * simd_distance(a, b)
		let control = (a + b) / 2 + SIMD3(0, apex, 0)
		let u = 1 - t
		return u * u * a + 2 * u * t * control + t * t * b
	}
}
#endif
