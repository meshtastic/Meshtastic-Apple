//
//  MeshTrafficMonitor.swift
//  Meshtastic
//
//  Tracks a rolling estimate of inbound mesh packets/second and exposes a debounced
//  "traffic is high" flag. The map uses it to gate the trace-route 3D flyover: that
//  flyover drives the MKMapView camera on every display frame, and on a busy mesh it
//  has to compete with the SwiftUI re-renders that packet ingestion triggers, so the
//  flythrough stutters. Pausing the flyover above a traffic threshold keeps the map usable.
//

import Foundation
import QuartzCore

@MainActor
final class MeshTrafficMonitor: ObservableObject {
	/// True while sustained inbound mesh traffic is high enough that the trace-route flyover would
	/// render janky. Asymmetric watermarks plus a sustain delay keep it from flapping around the
	/// boundary — so a brief lull doesn't immediately re-enable a doomed flyover, and a single burst
	/// doesn't kill one already in flight.
	@Published private(set) var isHighTraffic = false

	/// Smoothed inbound mesh packets/second (an EWMA of the per-window samples), exposed as the
	/// underlying rate behind `isHighTraffic` for display/diagnostics. The gate itself keys off the
	/// raw per-window rate (see `sample`) so a single decaying burst can't drift it over the line.
	@Published private(set) var packetsPerSecond: Double = 0

	// MARK: - Tuning

	/// Trip `isHighTraffic` on once the smoothed rate holds at or above this many packets/second for
	/// `sustainSeconds`. Rationale: the flyover is an `MKMapCamera` animation stepping every display
	/// frame while node pins are already being re-rendered from ingestion; sustained inbound traffic
	/// in the mid-20s pkt/s is where the flythrough starts visibly stuttering on device.
	static let highWatermark: Double = 25
	/// Trip it back off once the smoothed rate falls below this. It sits below `highWatermark` so the
	/// gate has hysteresis and doesn't chatter when the rate hovers near the threshold.
	static let lowWatermark: Double = 15
	/// The smoothed rate must stay at or above `highWatermark` continuously for this long before the
	/// gate trips on, so a momentary spike neither blocks a launch nor stops a flyover already running.
	static let sustainSeconds: TimeInterval = 2
	/// How often the rate is resampled from the packet counter.
	static let sampleInterval: TimeInterval = 1
	/// EWMA time constant for the exposed `packetsPerSecond` display value (the gate keys off the raw
	/// per-window rate, not this). Larger means a steadier number but slower to reflect a change.
	private static let smoothingTimeConstant: TimeInterval = 1.5

	// MARK: - State

	private var pendingCount = 0
	private var lastSampleTime: TimeInterval = 0
	private var highSince: TimeInterval?
	private var timer: Timer?

	/// Record one inbound mesh packet. Deliberately cheap — it only bumps a counter (the rate is
	/// derived on the sampling timer), so it's safe to call from the hot per-packet ingestion path.
	func record() {
		pendingCount += 1
	}

	/// Begin sampling. Call when a connection becomes active. Idempotent.
	func start() {
		guard timer == nil else { return }
		lastSampleTime = CACurrentMediaTime()
		let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
			// The timer is scheduled on the main run loop, so its callback runs on the main actor.
			MainActor.assumeIsolated {
				self?.sample(now: CACurrentMediaTime())
			}
		}
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}

	/// Stop sampling and clear all state. Call on disconnect.
	func stop() {
		timer?.invalidate()
		timer = nil
		pendingCount = 0
		lastSampleTime = 0
		highSince = nil
		if packetsPerSecond != 0 { packetsPerSecond = 0 }
		if isHighTraffic { isHighTraffic = false }
	}

	/// Fold the packets counted since the last sample into the smoothed rate and re-evaluate the
	/// gate. Deterministic given `now` and the counted packets, so it's unit-testable without a real
	/// timer (drive it with `record()` calls followed by `sample(now:)`).
	func sample(now: TimeInterval) {
		let elapsed = lastSampleTime == 0 ? Self.sampleInterval : max(now - lastSampleTime, 0.001)
		lastSampleTime = now

		let rate = Double(pendingCount) / elapsed
		pendingCount = 0

		let alpha = 1 - exp(-elapsed / Self.smoothingTimeConstant)
		let smoothed = packetsPerSecond + (rate - packetsPerSecond) * alpha
		if smoothed != packetsPerSecond { packetsPerSecond = smoothed }

		updateGate(rate: rate, now: now)
	}

	/// Apply the hysteresis watermarks and sustain delay to the raw per-window `rate`, updating
	/// `isHighTraffic` at most once per sample. Keying off the raw rate (not the EWMA) means the
	/// sustain timer only advances while traffic is genuinely still high, so a lone burst — whose
	/// smoothed tail lingers above the line for a second or two — can't trip the gate on its own.
	private func updateGate(rate: Double, now: TimeInterval) {
		if isHighTraffic {
			if rate < Self.lowWatermark {
				isHighTraffic = false
				highSince = nil
			}
		} else if rate >= Self.highWatermark {
			if let since = highSince {
				if now - since >= Self.sustainSeconds { isHighTraffic = true }
			} else {
				highSince = now
			}
		} else {
			highSince = nil
		}
	}
}
