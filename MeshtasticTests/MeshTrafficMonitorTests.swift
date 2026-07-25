//
//  MeshTrafficMonitorTests.swift
//  MeshtasticTests
//
//  Covers the rolling mesh-traffic rate gate that pauses the map's trace-route flyover under heavy
//  live traffic. The rate logic (`record()` + `sample(now:)`) is deterministic given an injected
//  timestamp, so these tests drive it directly without spinning a real sampling timer.
//

import Foundation
import Testing

@testable import Meshtastic

@MainActor
@Suite("MeshTrafficMonitor rate gate")
struct MeshTrafficMonitorTests {

	/// Feed `count` packets into one sample window and advance the clock by one `sampleInterval`.
	/// Returns the new "now".
	@discardableResult
	private func step(_ monitor: MeshTrafficMonitor, packets count: Int, from now: TimeInterval) -> TimeInterval {
		let next = now + MeshTrafficMonitor.sampleInterval
		for _ in 0..<count { monitor.record() }
		monitor.sample(now: next)
		return next
	}

	/// Drive `count` packets/second for `seconds` samples. Returns the new "now".
	@discardableResult
	private func run(_ monitor: MeshTrafficMonitor, packetsPerSecond count: Int, seconds: Int, from now: TimeInterval) -> TimeInterval {
		var t = now
		for _ in 0..<seconds { t = step(monitor, packets: count, from: t) }
		return t
	}

	@Test("Thresholds are ordered so the gate has real hysteresis")
	func thresholdsHaveHysteresis() {
		#expect(MeshTrafficMonitor.lowWatermark < MeshTrafficMonitor.highWatermark)
		#expect(MeshTrafficMonitor.sustainSeconds > 0)
	}

	@Test("Quiet traffic never trips the gate")
	func quietStaysLow() {
		let monitor = MeshTrafficMonitor()
		run(monitor, packetsPerSecond: 3, seconds: 30, from: 0)
		#expect(monitor.isHighTraffic == false)
		#expect(monitor.packetsPerSecond < MeshTrafficMonitor.lowWatermark)
	}

	@Test("Sustained heavy traffic trips the gate")
	func heavyTrips() {
		let monitor = MeshTrafficMonitor()
		run(monitor, packetsPerSecond: 40, seconds: 10, from: 0)
		#expect(monitor.isHighTraffic == true)
		#expect(monitor.packetsPerSecond >= MeshTrafficMonitor.highWatermark)
	}

	@Test("The gate waits out the sustain window before tripping")
	func sustainDelaysTheTrip() {
		let monitor = MeshTrafficMonitor()
		// One sample above the high watermark is not enough on its own.
		step(monitor, packets: 40, from: 0)
		#expect(monitor.isHighTraffic == false)
	}

	@Test("A single burst does not trip the gate")
	func singleBurstIgnored() {
		let monitor = MeshTrafficMonitor()
		// A lone spike far above the high watermark, then silence — the smoothed rate's decaying
		// tail must not be mistaken for sustained traffic.
		var t = step(monitor, packets: 300, from: 0)
		t = run(monitor, packetsPerSecond: 0, seconds: 6, from: t)
		#expect(monitor.isHighTraffic == false)
	}

	@Test("The gate clears once traffic falls below the resume watermark")
	func recoversWhenTrafficDrops() {
		let monitor = MeshTrafficMonitor()
		var t = run(monitor, packetsPerSecond: 40, seconds: 10, from: 0)
		#expect(monitor.isHighTraffic == true)
		t = run(monitor, packetsPerSecond: 0, seconds: 3, from: t)
		#expect(monitor.isHighTraffic == false)
	}

	@Test("Mid-band traffic holds an already-tripped gate high (hysteresis)")
	func hysteresisHoldsHigh() {
		let monitor = MeshTrafficMonitor()
		var t = run(monitor, packetsPerSecond: 40, seconds: 10, from: 0)
		#expect(monitor.isHighTraffic == true)
		// A rate between the low and high watermarks must NOT clear a gate that is already high.
		let midBand = Int((MeshTrafficMonitor.lowWatermark + MeshTrafficMonitor.highWatermark) / 2)
		t = run(monitor, packetsPerSecond: midBand, seconds: 10, from: t)
		#expect(monitor.isHighTraffic == true)
	}

	@Test("Mid-band traffic from a quiet start never trips the gate")
	func midBandFromQuietStaysLow() {
		let monitor = MeshTrafficMonitor()
		let midBand = Int((MeshTrafficMonitor.lowWatermark + MeshTrafficMonitor.highWatermark) / 2)
		run(monitor, packetsPerSecond: midBand, seconds: 20, from: 0)
		#expect(monitor.isHighTraffic == false)
	}

	@Test("stop() clears the gate and resets the rate")
	func stopResets() {
		let monitor = MeshTrafficMonitor()
		run(monitor, packetsPerSecond: 40, seconds: 10, from: 0)
		#expect(monitor.isHighTraffic == true)
		monitor.stop()
		#expect(monitor.isHighTraffic == false)
		#expect(monitor.packetsPerSecond == 0)
	}
}
