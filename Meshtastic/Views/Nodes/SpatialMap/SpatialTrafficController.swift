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
/// the sender to the connected radio, the activity halo under each node, and a flyover marker.
@MainActor
final class SpatialTrafficController {
	static let poolSize = 24

	private struct Pulse {
		let entity: ModelEntity
		let from: SIMD3<Float>
		let to: SIMD3<Float>
		let duration: TimeInterval
		var elapsed: TimeInterval = 0
	}

	private let scene: SpatialSceneController
	private static let pulseMesh = MeshResource.generateSphere(radius: 0.007)
	private static let markerMesh = MeshResource.generateSphere(radius: 0.008)
	private var idle: [ModelEntity] = []
	private var active: [Pulse] = []
	private var limiter = PulseRateLimiter()
	private var boosts: [Int64: (start: TimeInterval, initial: Float)] = [:]
	private var clock: TimeInterval = 0
	private var flyover: SpatialFlyover?
	private let marker: ModelEntity
	private(set) var flyingRouteID: Int64?

	var showPulses = true
	var showGlow = true { didSet { if !showGlow { clearHalos() } } }
	var isHighTraffic = false
	var preset: ModemPresets = .longFast
	var connectedNodeNum: Int64?
	var isFlying: Bool { flyover != nil }

	init(scene: SpatialSceneController) {
		self.scene = scene
		marker = ModelEntity(mesh: Self.markerMesh, materials: [UnlitMaterial(color: .white)])
		marker.isEnabled = false
		scene.trafficContainer.addChild(marker)
		for _ in 0..<Self.poolSize {
			let entity = ModelEntity(mesh: Self.pulseMesh, materials: [UnlitMaterial(color: .white)])
			entity.isEnabled = false
			scene.trafficContainer.addChild(entity)
			idle.append(entity)
		}
	}

	// MARK: Packets

	func handle(_ event: MeshPacketEvent) {
		if showGlow { boosts[event.from] = (clock, 1) }
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

	// MARK: Flyover

	func startFlyover(_ route: SpatialRouteSnapshot) {
		guard let placement = scene.placement else { return }
		let legs = [route.forward, route.back].map { path in
			path.map {
				SpatialZoom.clampToDisk(placement.surface($0.coordinate, clearance: SpatialSceneController.flyHeight), diskRadius: placement.diskRadius)
			}
		}
		let flyover = SpatialFlyover(legs: legs)
		guard !flyover.legs.isEmpty else { return }
		self.flyover = flyover
		flyingRouteID = route.id
		scene.showRoute(legs: legs.map { $0.map { $0 - [0, 0.03, 0] } }, color: UIColor(getSnrColor(snr: route.forward.last?.snr ?? 0, preset: preset)))
		marker.scale = SIMD3(repeating: scene.counterScale)
		marker.isEnabled = true
	}

	func stopFlyover() {
		flyover = nil
		flyingRouteID = nil
		marker.isEnabled = false
		scene.showRoute(legs: [], color: .white)
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
		if !boosts.isEmpty {
			for (num, boost) in boosts {
				let value = NodeActivityGlow.boost(startedAt: boost.start, now: clock, initial: boost.initial)
				let base = scene.baseGlow(num)
				scene.setHalo(num, opacity: NodeActivityGlow.opacity(base: base, boost: value), scale: NodeActivityGlow.scale(boost: value))
				if value < NodeActivityGlow.boostFloor { boosts[num] = nil }
			}
		}
		if var flyover {
			if let position = flyover.advance(by: dt) {
				marker.position = position
				self.flyover = flyover
			} else {
				stopFlyover()
			}
		}
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
