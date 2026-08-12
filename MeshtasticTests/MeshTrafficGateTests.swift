// MARK: MeshTrafficGateTests
//
//  Locks down the pure hysteresis + debounce state machine that turns a continuous inbound
//  mesh-packet rate into the single `isHighTraffic` flag used to gate the trace-route map flyover.
//  Verifies: a brief spike is ignored (debounce), a sustained high rate trips only after the debounce
//  window, and the flag doesn't chatter around the threshold (hysteresis).
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("MeshTrafficGate")
struct MeshTrafficGateTests {

	private let high = 25.0
	private let low = 15.0
	private let sustain = 2.0

	private func step(_ gate: inout MeshTrafficGate, rate: Double, now: TimeInterval) {
		gate.update(rate: rate, now: now, highThreshold: high, lowThreshold: low, sustain: sustain)
	}

	@Test("A rate below the high threshold never trips the gate")
	func lowRateStaysNormal() {
		var gate = MeshTrafficGate()
		step(&gate, rate: 10, now: 0)
		step(&gate, rate: 24.9, now: 5)
		step(&gate, rate: 14, now: 10)
		#expect(gate.isHigh == false)
	}

	@Test("A brief spike shorter than the debounce window does not trip the gate")
	func briefSpikeIgnored() {
		var gate = MeshTrafficGate()
		step(&gate, rate: 40, now: 0)    // high spell begins
		step(&gate, rate: 40, now: 1)    // still inside the 2s debounce
		step(&gate, rate: 5, now: 1.5)   // dropped before the debounce elapsed
		#expect(gate.isHigh == false)
	}

	@Test("A sustained high rate trips the gate once the debounce window elapses")
	func sustainedHighTrips() {
		var gate = MeshTrafficGate()
		step(&gate, rate: 30, now: 0)    // debounce begins
		#expect(gate.isHigh == false)
		step(&gate, rate: 30, now: 1.9)  // not yet 2s
		#expect(gate.isHigh == false)
		step(&gate, rate: 30, now: 2.0)  // 2s elapsed -> trips
		#expect(gate.isHigh == true)
	}

	@Test("Hysteresis: once high, it stays high between the low and high thresholds")
	func staysHighInHysteresisBand() {
		var gate = MeshTrafficGate()
		step(&gate, rate: 30, now: 0)
		step(&gate, rate: 30, now: 2)    // high now
		#expect(gate.isHigh == true)
		step(&gate, rate: 20, now: 3)    // between low (15) and high (25)
		#expect(gate.isHigh == true)
		step(&gate, rate: 15, now: 4)    // at the low threshold, not below -> still high
		#expect(gate.isHigh == true)
	}

	@Test("Drops back to normal only once the rate falls below the low threshold")
	func dropsBelowLowResumesNormal() {
		var gate = MeshTrafficGate()
		step(&gate, rate: 30, now: 0)
		step(&gate, rate: 30, now: 2)
		#expect(gate.isHigh == true)
		step(&gate, rate: 14.9, now: 3)  // below the low threshold -> normal
		#expect(gate.isHigh == false)
	}

	@Test("The debounce restarts if the rate dips below high and returns")
	func debounceRestartsAfterDip() {
		var gate = MeshTrafficGate()
		step(&gate, rate: 30, now: 0)    // debounce begins at t=0
		step(&gate, rate: 10, now: 1)    // dip clears the debounce
		step(&gate, rate: 30, now: 1.5)  // debounce restarts at t=1.5
		step(&gate, rate: 30, now: 3.0)  // only 1.5s since restart, < 2s
		#expect(gate.isHigh == false)
		step(&gate, rate: 30, now: 3.5)  // 2s since restart -> trips
		#expect(gate.isHigh == true)
	}
}
