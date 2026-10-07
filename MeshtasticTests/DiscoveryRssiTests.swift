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

	@Test("A radio's RSSI is shown when it moved 5 dB after 2 s, or after 5 s, not on every report")
	func showsRssi() {
		let shown = AccessoryManager.ShownRssi(rssi: -60, at: at(0))
		#expect(AccessoryManager.showsDiscoveryRssi(-60, at: at(0), after: nil), "the first one")
		#expect(!AccessoryManager.showsDiscoveryRssi(-62, at: at(1), after: shown))
		#expect(!AccessoryManager.showsDiscoveryRssi(-56, at: at(4.9), after: shown))
		#expect(!AccessoryManager.showsDiscoveryRssi(-80, at: at(1.9), after: shown), "not within 2 s, however far it moved")
		#expect(AccessoryManager.showsDiscoveryRssi(-65, at: at(2), after: shown), "moved 5 dB")
		#expect(AccessoryManager.showsDiscoveryRssi(-55, at: at(2), after: shown))
		#expect(AccessoryManager.showsDiscoveryRssi(-61, at: at(5), after: shown), "5 s passed")
	}

	@Test("Discovery writes only the RSSIs worth showing into the radio list")
	func discoveryListThrottled() async throws {
		let radio = Device(id: UUID(), name: "Far", transportType: .tcp, identifier: "far.local:4403", rssi: -60)
		// Found after the others, so once it's listed they've all been handled.
		let last = Device(id: UUID(), name: "Last", transportType: .tcp, identifier: "last.local:4403", rssi: -50)
		let manager = AccessoryManager(transports: [ScriptedDiscoveryTransport(events: [
			.deviceFound(radio),
			.deviceReportedRssi(radio.id, -61),
			.deviceReportedRssi(radio.id, -63),
			.deviceReportedRssi(radio.id, -62),
			.deviceReportedRssi(radio.id, -70),
			.deviceFound(last)
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
		for _ in 0..<200 where !manager.devices.contains(where: { $0.id == last.id }) {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(manager.devices.contains { $0.id == last.id })
		#expect(shown == [-60, -61], "-63 and -62 are within 5 dB of -61, and -70 came within 2 s")
	}
}

@MainActor
@Suite("Discovery after the Connect screen", .serialized)
struct DiscoveryAfterConnectScreenTests {
	@Test("Discovery stops once nothing needs it: no Connect screen, a radio connected, the first radio not awaited, no remembered radio awaited")
	func stopsWhenUnneeded() {
		let saved = ConnectFlowSupport.SavedDefaults()
		let autoconnect = UserDefaults.autoconnectOnDiscovery
		defer {
			saved.restore()
			UserDefaults.autoconnectOnDiscovery = autoconnect
		}
		let manager = AccessoryManager(transports: [ScriptedDiscoveryTransport(events: [])])
		manager.isSwitchingDevices = true
		manager.startDiscovery()
		defer {
			manager.rememberedRadioFallbackTask?.cancel()
			manager.stopDiscovery()
		}
		manager.stopDiscoveryWhenUnneeded()
		#expect(manager.discoveryTask != nil, "nothing connected: it goes on, as on main")

		// A radio alongside connected, the first radio away after a drop.
		var radio = Device(id: UUID(), name: "Near", transportType: .tcp, identifier: "near.local:4403")
		radio.num = 0x0A0A
		manager.additionalRadios[radio.id] = RadioSession(device: radio, connection: ScriptedRadio(nodeNum: 0x0A0A))
		PreferredRadio.peripheralId = UUID().uuidString
		UserDefaults.autoconnectOnDiscovery = true
		manager.stopDiscoveryWhenUnneeded()
		#expect(manager.discoveryTask != nil, "the first radio comes back through it")

		manager.userRequestedConnectionCancellation = true
		manager.stopDiscoveryWhenUnneeded()
		#expect(manager.discoveryTask == nil, "the user disconnected the first radio")
		manager.userRequestedConnectionCancellation = false
		manager.startDiscovery()

		// The first radio connected.
		manager.updateState(.subscribed)
		manager.awaitedRememberedRadios.insert(UUID())
		manager.stopDiscoveryWhenUnneeded()
		#expect(manager.discoveryTask != nil, "a remembered radio still waits to be found")
		manager.awaitedRememberedRadios.removeAll()

		let screen = UUID()
		manager.connectScreenAppeared(screen)
		manager.stopDiscoveryWhenUnneeded()
		#expect(manager.discoveryTask != nil, "a Connect screen shows")
		manager.connectScreenDisappeared(screen)
		#expect(manager.discoveryTask == nil, "it stops with the screen")
	}
}

@MainActor
@Suite("Discovery after a connect alongside", .serialized, .timeLimit(.minutes(1)))
struct DiscoveryAfterConnectTests {
	@Test("A radio connecting alongside stops discovery once nothing needs it, as the only radio's connect does")
	func connectAlongsideStopsIt() async throws {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let firstNum = ConnectFlowSupport.uniqueNodeNum()
		let secondDevice = ConnectFlowSupport.device()
		let thirdDevice = ConnectFlowSupport.device()
		let transport = ScriptedTransport(radio: ScriptedRadio(nodeNum: firstNum), radiosByIdentifier: [
			secondDevice.identifier: ScriptedRadio(nodeNum: firstNum &+ 0x100),
			thirdDevice.identifier: ScriptedRadio(nodeNum: firstNum &+ 0x200)
		])
		let manager = ConnectFlowSupport.makeManager(transport)
		try await manager.connect(to: ConnectFlowSupport.device())
		manager.awaitedRememberedRadios.removeAll()

		// Started again by the first radio's drop, or left by a Connect screen.
		manager.startDiscovery()
		try await manager.connectAdditionalRadio(secondDevice)
		#expect(manager.discoveryTask == nil)

		let screen = UUID()
		manager.connectScreenAppeared(screen)
		manager.startDiscovery()
		try await manager.connectAdditionalRadio(thirdDevice)
		#expect(manager.discoveryTask != nil, "not while a Connect screen shows")
		manager.connectScreenDisappeared(screen)
		#expect(manager.discoveryTask == nil)

		await manager.disconnectAdditionalRadio(secondDevice.id, byUser: true)
		await manager.disconnectAdditionalRadio(thirdDevice.id, byUser: true)
		try await manager.disconnect()
	}
}
