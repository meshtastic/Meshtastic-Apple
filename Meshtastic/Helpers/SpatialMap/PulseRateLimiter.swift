//
//  PulseRateLimiter.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import Foundation

/// Decides which packets get a traffic pulse: a token bucket for the overall rate, a minimum gap
/// per sender, and nothing at all while the mesh is busy enough to pause the map flyover.
struct PulseRateLimiter {
	let capacity: Double
	let refillPerSecond: Double
	let perSenderInterval: TimeInterval
	private var tokens: Double
	private var lastRefill: TimeInterval?
	private var lastBySender: [Int64: TimeInterval] = [:]
	private(set) var dropped = 0

	init(capacity: Double = 6, refillPerSecond: Double = 6, perSenderInterval: TimeInterval = 0.3) {
		self.capacity = capacity
		self.refillPerSecond = refillPerSecond
		self.perSenderInterval = perSenderInterval
		tokens = capacity
	}

	mutating func admit(sender: Int64, now: TimeInterval, highTraffic: Bool) -> Bool {
		if let lastRefill {
			tokens = min(capacity, tokens + max(0, now - lastRefill) * refillPerSecond)
		}
		lastRefill = now
		if highTraffic {
			dropped += 1
			return false
		}
		if let last = lastBySender[sender], now - last < perSenderInterval {
			dropped += 1
			return false
		}
		guard tokens >= 1 else {
			dropped += 1
			return false
		}
		tokens -= 1
		lastBySender[sender] = now
		if lastBySender.count > 2_000 {
			lastBySender = lastBySender.filter { now - $0.value < perSenderInterval }
		}
		return true
	}
}
