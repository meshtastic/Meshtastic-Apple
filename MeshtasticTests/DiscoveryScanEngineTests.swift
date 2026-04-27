// MARK: DiscoveryScanEngineTests

import Foundation
import Testing

@testable import Meshtastic

@Suite("DiscoveryScanEngine")
struct DiscoveryScanEngineTests {

	// MARK: - Initial State

	@Test func initialStateIsIdle() async {
		let engine = await DiscoveryScanEngine()
		let state = await engine.currentState
		#expect(state == .idle)
	}

	@Test func isScanningFalseWhenIdle() async {
		let engine = await DiscoveryScanEngine()
		let scanning = await engine.isScanning
		#expect(!scanning)
	}

	@Test func defaultDwellDurationIs900() async {
		let engine = await DiscoveryScanEngine()
		let dwell = await engine.dwellDuration
		#expect(dwell == 900)
	}

	// MARK: - Start Scan Guards

	@Test func startScanFailsWithNoPresets() async {
		let engine = await DiscoveryScanEngine()
		await engine.startScan()
		let state = await engine.currentState
		#expect(state == .idle)
	}

	@Test func startScanFailsWithoutConnection() async {
		let engine = await DiscoveryScanEngine()
		await MainActor.run {
			engine.selectedPresets = [.longFast]
		}
		await engine.startScan()
		let state = await engine.currentState
		#expect(state == .idle)
	}

	// MARK: - State Enumeration

	@Test func allScanStatesExist() {
		let states: [DiscoveryScanState] = [
			.idle, .shifting, .reconnecting, .dwell,
			.analysis, .complete, .paused, .restoring
		]
		#expect(states.count == 8)
	}

	@Test func scanStatesEquality() {
		#expect(DiscoveryScanState.idle == DiscoveryScanState.idle)
		#expect(DiscoveryScanState.dwell != DiscoveryScanState.shifting)
	}

	// MARK: - isScanning States

	@Test func activeScanStatesReturnTrue() async {
		let engine = await DiscoveryScanEngine()
		// Test via the computed property definition
		let activeStates: [DiscoveryScanState] = [.shifting, .reconnecting, .dwell, .paused, .restoring]
		for state in activeStates {
			await MainActor.run {
				engine.currentState = state
			}
			let scanning = await engine.isScanning
			#expect(scanning, "Expected isScanning=true for state \(state)")
		}
	}

	@Test func inactiveScanStatesReturnFalse() async {
		let engine = await DiscoveryScanEngine()
		let inactiveStates: [DiscoveryScanState] = [.idle, .analysis, .complete]
		for state in inactiveStates {
			await MainActor.run {
				engine.currentState = state
			}
			let scanning = await engine.isScanning
			#expect(!scanning, "Expected isScanning=false for state \(state)")
		}
	}
}
