// MARK: CoverageEstimateCoordinatorTests
//
//  Covers the pure state-machine behavior of CoverageEstimateCoordinator (FR-007/FR-008)
//  without depending on a real network round trip — `start()` transitions to `.running`
//  synchronously before the bridge's async work begins, so the one-in-flight rule and
//  validation short-circuit are both testable without waiting on site.meshtastic.org.
//
//  Serialized: all tests share the `.shared` singleton's mutable state.
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("CoverageEstimateCoordinator", .serialized)
@MainActor
struct CoverageEstimateCoordinatorTests {

	private func validParams() -> CoverageEstimateParameters {
		CoverageEstimateParameters(
			name: "Test", latitude: 47.6062, longitude: -122.3321,
			transmitPowerWatts: 0.1, transmitFrequencyMHz: 915
		)
	}

	@Test func startTransitionsToRunning() {
		let coordinator = CoverageEstimateCoordinator.shared
		coordinator.reset()

		coordinator.start(validParams())
		defer { coordinator.reset() }

		guard case .running = coordinator.state else {
			Issue.record("expected .running, got \(coordinator.state)")
			return
		}
	}

	@Test func secondStartWhileRunningIsIgnored() {
		let coordinator = CoverageEstimateCoordinator.shared
		coordinator.reset()

		coordinator.start(validParams())
		defer { coordinator.reset() }

		guard case .running(let firstStartedAt) = coordinator.state else {
			Issue.record("expected .running after first start()")
			return
		}

		var second = validParams()
		second.name = "Should Be Ignored"
		coordinator.start(second)

		guard case .running(let secondStartedAt) = coordinator.state else {
			Issue.record("expected still .running after ignored second start()")
			return
		}
		#expect(firstStartedAt == secondStartedAt) // unchanged — the second call was a no-op
	}

	@Test func invalidParametersFailWithoutStartingTheBridge() {
		let coordinator = CoverageEstimateCoordinator.shared
		coordinator.reset()

		var invalid = validParams()
		invalid.latitude = 0
		invalid.longitude = 0
		coordinator.start(invalid)
		defer { coordinator.reset() }

		guard case .failed = coordinator.state else {
			Issue.record("expected .failed for invalid params, got \(coordinator.state)")
			return
		}
	}

	@Test func resetWhileIdleIsSafe() {
		let coordinator = CoverageEstimateCoordinator.shared
		coordinator.reset()
		#expect(coordinator.state == .idle)

		coordinator.reset() // must not throw / must not change state
		#expect(coordinator.state == .idle)
	}

	@Test func acknowledgeReturnsToIdleFromATerminalState() {
		let coordinator = CoverageEstimateCoordinator.shared
		coordinator.reset()

		var invalid = validParams()
		invalid.latitude = 0
		invalid.longitude = 0
		coordinator.start(invalid) // synchronously lands in .failed
		defer { coordinator.reset() }

		guard case .failed = coordinator.state else {
			Issue.record("expected .failed before acknowledge()")
			return
		}
		coordinator.acknowledge()
		#expect(coordinator.state == .idle)
	}

	@Test func acknowledgeIsNoOpWhileRunning() {
		let coordinator = CoverageEstimateCoordinator.shared
		coordinator.reset()

		coordinator.start(validParams())
		defer { coordinator.reset() }

		coordinator.acknowledge()
		guard case .running = coordinator.state else {
			Issue.record("expected acknowledge() to be a no-op while .running")
			return
		}
	}
}
