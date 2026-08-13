//
//  MeshTrafficMonitor.swift
//  Meshtastic
//
//  Tracks how fast inbound mesh packets are arriving so heavy-weight UI (notably the trace-route
//  3D flyover, a per-frame MapKit camera animation) can back off when live traffic would make it
//  render uselessly slow. The rate is a rolling average over a short window; a hysteresis +
//  debounce gate turns that continuous rate into a single, rarely-flipping `isHighTraffic` flag the
//  views can observe without being re-rendered on every packet.
//

import Foundation
import QuartzCore
import OSLog

/// Pure, value-typed hysteresis + debounce state machine for the "traffic is high" decision. Kept
/// free of clocks and timers so it can be unit-tested deterministically (callers pass `now`).
///
/// Two thresholds (hysteresis) stop it oscillating when the rate hovers near the line, and a
/// `sustain` window (debounce) means a brief burst won't trip it — the high rate has to persist.
struct MeshTrafficGate: Equatable {
	/// True once the rate has stayed at/above `highThreshold` for `sustain` seconds; drops back to
	/// false only once the rate falls below `lowThreshold`.
	private(set) var isHigh = false
	/// Monotonic time the rate first reached `highThreshold` in the current (not-yet-high) spell,
	/// or nil when the rate is below the high line. Drives the debounce.
	private var highSince: TimeInterval?

	/// Feed the latest smoothed rate (packets/sec) sampled at monotonic time `now` (seconds).
	mutating func update(rate: Double, now: TimeInterval, highThreshold: Double, lowThreshold: Double, sustain: TimeInterval) {
		if isHigh {
			// Already gated — only step down once we clear the lower (hysteresis) threshold.
			if rate < lowThreshold {
				isHigh = false
				highSince = nil
			}
		} else if rate >= highThreshold {
			// At/above the high line: start (or continue) the debounce, and flip once it's held.
			if let since = highSince {
				if now - since >= sustain { isHigh = true }
			} else {
				highSince = now
			}
		} else {
			// Dropped below the high line before the debounce elapsed — reset it.
			highSince = nil
		}
	}
}

/// Observable, main-actor rolling counter of inbound mesh packets. `AccessoryManager` calls
/// `recordInboundPacket()` for every received mesh packet; views observe `isHighTraffic`.
///
/// Only the coarse `isHighTraffic` bool is `@Published`, and it flips only on sustained threshold
/// crossings, so observing it costs a re-render just a couple of times per traffic surge — not once
/// per packet. The underlying rate is intentionally *not* published for that reason.
@MainActor
final class MeshTrafficMonitor: ObservableObject {
	static let shared = MeshTrafficMonitor()

	// MARK: Tuning — single source of truth, deliberately easy to adjust.

	/// Window (seconds) the packet rate is averaged over. Long enough to smooth the bursty nature of
	/// mesh traffic (packets arrive in clumps), short enough to react within a couple of seconds.
	static let windowSeconds: TimeInterval = 4

	/// Enter "high traffic" at/above this many inbound packets/sec (sustained — see `sustainSeconds`).
	/// The trace-route flyover is a per-frame MapKit camera animation that already contends with the
	/// SwiftUI re-renders our packet ingestion drives; past roughly this rate the flythrough stutters
	/// badly enough to be useless, so we gate it here. Tuned conservatively toward the high end of the
	/// "this will be janky" band so we only disable the flyover when traffic really is heavy.
	static let highThreshold: Double = 25

	/// Drop back to "normal" only once the rate falls below this (hysteresis, ~60% of the high line)
	/// so the flag doesn't chatter while traffic hovers near the threshold.
	static let lowThreshold: Double = 15

	/// The rate must stay at/above `highThreshold` for at least this long before we gate (debounce),
	/// so a momentary burst doesn't yank a flyover that would otherwise have played fine.
	static let sustainSeconds: TimeInterval = 2

	/// How often the decay timer re-samples the rate so it falls back to normal after traffic stops
	/// (no packets arrive to drive `recordInboundPacket`, so a timer has to age the window out).
	private static let tickInterval: TimeInterval = 0.5

	// MARK: State

	/// True while inbound mesh traffic is high enough to suppress the trace-route flyover.
	@Published private(set) var isHighTraffic = false

	/// Latest smoothed inbound rate (packets/sec). Not `@Published` — updates too often; exposed for
	/// logging / debugging only.
	private(set) var packetsPerSecond: Double = 0

	/// Monotonic arrival times (seconds) of packets still inside the averaging window.
	private var timestamps: [TimeInterval] = []
	private var gate = MeshTrafficGate()
	private var decayTimer: Timer?

	private init() {}

	/// Record one inbound mesh packet. Called on the main actor from `AccessoryManager`'s packet
	/// dispatch. Cheap: appends a timestamp and re-evaluates the (small) window.
	func recordInboundPacket() {
		let now = CACurrentMediaTime()
		timestamps.append(now)
		startTimerIfNeeded()
		evaluate(now: now)
	}

	/// Clear all state (call on connect/disconnect so a stale window from the previous session can't
	/// leak into the next one).
	func reset() {
		timestamps.removeAll(keepingCapacity: true)
		gate = MeshTrafficGate()
		packetsPerSecond = 0
		if isHighTraffic { isHighTraffic = false }
		stopTimer()
	}

	// MARK: Internals

	private func evaluate(now: TimeInterval) {
		// Age packets out of the trailing window.
		let cutoff = now - Self.windowSeconds
		if let firstFresh = timestamps.firstIndex(where: { $0 >= cutoff }) {
			if firstFresh > 0 { timestamps.removeFirst(firstFresh) }
		} else {
			timestamps.removeAll(keepingCapacity: true)
		}

		let rate = Double(timestamps.count) / Self.windowSeconds
		packetsPerSecond = rate
		gate.update(rate: rate, now: now, highThreshold: Self.highThreshold, lowThreshold: Self.lowThreshold, sustain: Self.sustainSeconds)

		// Assign only on a real transition so we don't republish (and re-render) needlessly.
		if gate.isHigh != isHighTraffic {
			isHighTraffic = gate.isHigh
			Logger.services.info("🗺️ [MeshTraffic] isHighTraffic → \(self.isHighTraffic, privacy: .public) at \(String(format: "%.1f", rate), privacy: .public) pkts/s")
		}

		// Once the window has drained and we're back to normal, stop ticking to save power; the next
		// packet restarts the timer.
		if timestamps.isEmpty && !gate.isHigh {
			stopTimer()
		}
	}

	private func startTimerIfNeeded() {
		guard decayTimer == nil else { return }
		let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
			// Fires on the main run loop; hop to the main actor to touch isolated state.
			Task { @MainActor in self?.evaluate(now: CACurrentMediaTime()) }
		}
		RunLoop.main.add(timer, forMode: .common)
		decayTimer = timer
	}

	private func stopTimer() {
		decayTimer?.invalidate()
		decayTimer = nil
	}
}
