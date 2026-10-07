//
//  DiscoveryRssiTests.swift
//  MeshtasticTests
//
//  Feature 021, review V39: discovery shows a radio's RSSI only when it moved or time passed, so
//  scanning's report of every advertisement doesn't redraw every window several times a second.
//

import Combine
import Foundation
import Testing
@testable import Meshtastic

/// A transport whose discovery reports `events`, then waits.
private final class ScriptedDiscoveryTransport: Transport, @unchecked Sendable {
	let type: TransportType = .tcp
	var status: TransportStatus { .ready }
	let requiresPeriodicHeartbeat = false
	let supportsManualConnection = false
	let events: [DiscoveryEvent]

	init(events: [DiscoveryEvent]) { self.events = events }

	func discoverDevices() async -> AsyncStream<DiscoveryEvent> {
		let events = events
		return AsyncStream { continuation in
			for event in events { continuation.yield(event) }
		}
	}
	func connect(to device: Device) async throws -> any Connection {
		throw AccessoryError.connectionFailed("Not for this test")
	}
	func device(forManualConnection: String) -> Device? { nil }
	func manuallyConnect(toDevice: Device) async throws {}
}

@MainActor
@Suite("Discovery's RSSI")
struct DiscoveryRssiTests {
	private let start = ContinuousClock.now

	private func at(_ seconds: Double) -> ContinuousClock.Instant {
		start.advanced(by: .milliseconds(Int(seconds * 1000)))
	}

	@Test("A radio's RSSI is shown when it moved 5 dB or 5 s have passed, not on every report")
	func showsRssi() {
		let shown = AccessoryManager.ShownRssi(rssi: -60, at: at(0))
		#expect(AccessoryManager.showsDiscoveryRssi(-60, at: at(0), after: nil), "the first one")
		#expect(!AccessoryManager.showsDiscoveryRssi(-62, at: at(1), after: shown))
		#expect(!AccessoryManager.showsDiscoveryRssi(-56, at: at(4.9), after: shown))
		#expect(AccessoryManager.showsDiscoveryRssi(-65, at: at(1), after: shown), "moved 5 dB")
		#expect(AccessoryManager.showsDiscoveryRssi(-55, at: at(1), after: shown))
		#expect(AccessoryManager.showsDiscoveryRssi(-61, at: at(5), after: shown), "5 s passed")
	}

	@Test("Discovery writes only the RSSIs worth showing into the radio list")
	func discoveryListThrottled() async throws {
		let radio = Device(id: UUID(), name: "Far", transportType: .tcp, identifier: "far.local:4403", rssi: -60)
		let manager = AccessoryManager(transports: [ScriptedDiscoveryTransport(events: [
			.deviceFound(radio),
			.deviceReportedRssi(radio.id, -61),
			.deviceReportedRssi(radio.id, -63),
			.deviceReportedRssi(radio.id, -62),
			.deviceReportedRssi(radio.id, -70)
		])])
		manager.isSwitchingDevices = true
		var shown: [Int?] = []
		let subscription = manager.$devices.sink { devices in
			// The values in turn: finding a radio writes the list twice with the same one.
			if let rssi = devices.first(where: { $0.id == radio.id })?.rssi, shown.last != rssi { shown.append(rssi) }
		}
		defer {
			subscription.cancel()
			manager.rememberedRadioFallbackTask?.cancel()
			manager.stopDiscovery()
		}
		manager.startDiscovery()
		for _ in 0..<200 where manager.devices.first?.rssi != -70 {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(shown == [-60, -61, -70], "-63 and -62 are within 5 dB of -61, a moment later")
	}
}
