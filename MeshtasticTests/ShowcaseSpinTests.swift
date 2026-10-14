//
//  ShowcaseSpinTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Showcase inspection spin and display rows")
struct ShowcaseSpinTests {

	@Test("A sideways drag spins it, an upward drag tips it away, and tipping stops short of upside down")
	func drag() {
		var spin = ShowcaseSpin()
		spin.drag(offset: SIMD2(0.1, 0), at: 0)
		#expect(abs(spin.yaw - 0.1 * ShowcaseSpin.radiansPerMeter) < 1e-5)
		#expect(spin.pitch == 0)
		spin.drag(offset: SIMD2(0.1, 0.05), at: 0.1)
		#expect(spin.pitch < 0)
		spin.drag(offset: SIMD2(0.1, 1), at: 0.2)
		#expect(spin.pitch == -ShowcaseSpin.maxPitch)
		// A new drag starts from where the last one left it.
		spin.endDrag(reduceMotion: true)
		let yaw = spin.yaw
		spin.drag(offset: SIMD2(0.02, 0), at: 1)
		#expect(abs(spin.yaw - (yaw + 0.02 * ShowcaseSpin.radiansPerMeter)) < 1e-5)
	}

	@Test("A flick keeps turning and slows to a stop, unless motion is reduced")
	func coast() {
		var spin = ShowcaseSpin()
		spin.drag(offset: .zero, at: 0)
		spin.drag(offset: SIMD2(0.05, 0), at: 0.05)
		spin.endDrag(reduceMotion: false)
		let released = spin.yaw
		#expect(spin.isMoving)
		spin.step(0.1)
		#expect(spin.yaw > released)
		for _ in 0..<200 { spin.step(0.05) }
		#expect(!spin.isMoving)

		// A hand that stopped before letting go doesn't flick it.
		var stopped = ShowcaseSpin()
		stopped.drag(offset: .zero, at: 0)
		stopped.drag(offset: SIMD2(0.05, 0), at: 0.05)
		stopped.endDrag(reduceMotion: false, at: 0.5)
		#expect(!stopped.isMoving)

		// However hard the flick, it spins no faster than the cap.
		var hard = ShowcaseSpin()
		hard.drag(offset: .zero, at: 0)
		hard.drag(offset: SIMD2(5, 0), at: 0.01)
		#expect(simd_length(hard.velocity) <= ShowcaseSpin.maxSpeed + 1e-4)

		var still = ShowcaseSpin()
		still.drag(offset: .zero, at: 0)
		still.drag(offset: SIMD2(0.05, 0), at: 0.05)
		still.endDrag(reduceMotion: true)
		#expect(!still.isMoving)
	}

	@Test("Each maker's row fits its table, and the connected radio stands clear of the front row")
	func rows() {
		for vendor in ShowcaseVendor.allCases {
			let row = vendor.row
			#expect(abs(row.centerX) + row.length / 2 <= ShowcaseRoomGeometry.tableLength / 2 + 1e-5, "\(vendor)")
		}
		let front = ShowcaseVendor.rak.row
		#expect(ShowcaseDisplayRow.connectedRadio.x > front.centerX + front.length / 2)
	}
}
