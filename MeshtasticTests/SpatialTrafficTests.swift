//
//  SpatialTrafficTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("Spatial map traffic")
struct SpatialTrafficTests {

	@Test func pulsesBurstThenTrickle() {
		var limiter = PulseRateLimiter(capacity: 6, refillPerSecond: 6, perSenderInterval: 0.3)
		var admitted = 0
		for i in 0..<30 where limiter.admit(sender: Int64(i), now: 100, highTraffic: false) { admitted += 1 }
		#expect(admitted == 6)
		#expect(limiter.dropped == 24)
		// A second later the bucket has refilled.
		let later = limiter.admit(sender: 99, now: 101, highTraffic: false)
		#expect(later)
	}

	@Test func aSenderPulsesAtMostEveryThirdOfASecond() {
		var limiter = PulseRateLimiter()
		let first = limiter.admit(sender: 7, now: 10, highTraffic: false)
		let tooSoon = limiter.admit(sender: 7, now: 10.1, highTraffic: false)
		let later = limiter.admit(sender: 7, now: 10.4, highTraffic: false)
		#expect(first && !tooSoon && later)
	}

	@Test func highTrafficStopsAllPulses() {
		var limiter = PulseRateLimiter()
		let busy = limiter.admit(sender: 1, now: 0, highTraffic: true)
		let quiet = limiter.admit(sender: 1, now: 1, highTraffic: false)
		#expect(!busy && quiet)
	}

	@Test func glowTiersFollowLastHeard() {
		let now = Date(timeIntervalSince1970: 1_000_000)
		#expect(NodeActivityGlow.tier(lastHeard: nil, now: now) == .off)
		#expect(NodeActivityGlow.tier(lastHeard: now.addingTimeInterval(-30), now: now) == .live)
		#expect(NodeActivityGlow.tier(lastHeard: now.addingTimeInterval(-60), now: now) == .recent)
		#expect(NodeActivityGlow.tier(lastHeard: now.addingTimeInterval(-899), now: now) == .recent)
		#expect(NodeActivityGlow.tier(lastHeard: now.addingTimeInterval(-900), now: now) == .stale)
		#expect(NodeActivityGlow.tier(lastHeard: now.addingTimeInterval(-7_200), now: now) == .off)
		#expect(NodeActivityGlow.baseOpacity(.live) > NodeActivityGlow.baseOpacity(.recent))
	}

	@Test func aBoostFadesWithinSeconds() {
		#expect(NodeActivityGlow.boost(startedAt: 0, now: 0, initial: 1) == 1)
		#expect(NodeActivityGlow.boost(startedAt: 0, now: 6, initial: 1) < NodeActivityGlow.boostFloor)
		#expect(NodeActivityGlow.opacity(base: 0.2, boost: 0.8) == 0.8)
		#expect(NodeActivityGlow.opacity(base: 0.9, boost: 0.1) == 0.9)
		#expect(NodeActivityGlow.scale(boost: 1) == 1.4)
	}
}
