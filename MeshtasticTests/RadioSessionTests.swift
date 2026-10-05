//
//  RadioSessionTests.swift
//  MeshtasticTests
//
//  Copyright(c) Meshtastic 2026.
//

import Combine
import Foundation
import Testing

@testable import Meshtastic
import MeshtasticProtobufs

private actor IdleRadioConnection: Connection {
	let type: TransportType = .ble
	var isConnected = true

	func send(_ data: ToRadio) async throws {}
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws { isConnected = false }
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("Radio session", .serialized)
struct RadioSessionTests {
	private func makeSession(num: Int64? = 0x0000_BEEF) -> RadioSession {
		let device = Device(
			id: UUID(),
			name: "Session Test Radio",
			transportType: .ble,
			identifier: "session-test-radio",
			connectionState: .connected,
			num: num
		)
		return RadioSession(device: device, connection: IdleRadioConnection())
	}

	private func makeManager(active session: RadioSession) -> AccessoryManager {
		let manager = AccessoryManager(transports: [])
		manager.activeConnection = session
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		manager.updateState(.subscribed)
		return manager
	}

	/// A region preset map: it only sets the radio's `loRaRegionPresets`, which makes it a
	/// side-effect-free probe of whether a data event was handled, and for which radio. (A
	/// config-complete nothing waits on was the probe until #2404, which stamps
	/// `lastConfigRefresh` only on a completion a refresh owns.)
	private func probeEvent() -> ConnectionEvent {
		var group = LoRaPresetGroup()
		group.presets = [.longFast]
		group.defaultPreset = .longFast
		var entry = LoRaRegionPresets()
		entry.region = .us
		entry.groupIndex = 0
		var map = LoRaRegionPresetMap()
		map.groups = [group]
		map.regionGroups = [entry]
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .regionPresets(map)
		return .data(fromRadio)
	}

	private func wasHandled(by session: RadioSession) -> Bool {
		session.loRaRegionPresets[.us] != nil
	}

	@Test func sessionsAreDistinctPerConnectionAttempt() {
		let first = makeSession()
		let second = makeSession()
		#expect(first.id != second.id)
		#expect(first !== second)
		#expect(first.nodeNum == 0x0000_BEEF)
	}

	@Test func updateDeviceChangesTheSessionInPlaceAndNotifies() {
		let session = makeSession(num: nil)
		let manager = makeManager(active: session)
		var notifications = 0
		let cancellable = manager.objectWillChange.sink { notifications += 1 }
		defer { cancellable.cancel() }

		manager.updateDevice(deviceId: session.device.id, key: \.longName, value: "Renamed")
		#expect(session.device.longName == "Renamed")
		#expect(manager.activeConnection === session)
		#expect(notifications >= 1)

		manager.updateDevice(deviceId: session.device.id, key: \.num, value: Int64(0x1234))
		#expect(session.nodeNum == 0x1234)
		#expect(manager.activeDeviceNum == 0x1234)
	}

	/// T069: what a radio reports lives on its own session; the manager shows the first one's.
	@Test func reportedValuesStayWithTheirRadio() {
		let first = makeSession()
		let other = makeSession(num: 0x0000_CAFE)
		let manager = makeManager(active: first)
		var notifications = 0
		let cancellable = manager.objectWillChange.sink { notifications += 1 }
		defer { cancellable.cancel() }

		manager.update(other, \.firmwareEdition, to: .defcon)
		manager.update(other, \.expectedNodeDBSize, to: 42)
		#expect(other.firmwareEdition == .defcon)
		#expect(manager.firmwareEdition == .vanilla)
		#expect(manager.expectedNodeDBSize == nil)
		#expect(notifications == 0, "another radio's values don't redraw the first radio's views")

		manager.update(first, \.firmwareEdition, to: .burningMan)
		#expect(manager.firmwareEdition == .burningMan)
		#expect(notifications == 1)

		manager.activeConnection = other
		#expect(manager.firmwareEdition == .defcon)
		#expect(manager.expectedNodeDBSize == 42)
		manager.activeConnection = nil
		#expect(manager.firmwareEdition == .vanilla)
		#expect(manager.loRaRegionPresets.isEmpty)
	}

	@Test func updateDeviceWithTheSameValueDoesNotNotify() {
		let session = makeSession()
		let manager = makeManager(active: session)
		manager.updateDevice(deviceId: session.device.id, key: \.longName, value: "Same")
		var notifications = 0
		let cancellable = manager.objectWillChange.sink { notifications += 1 }
		defer { cancellable.cancel() }
		manager.updateDevice(deviceId: session.device.id, key: \.longName, value: "Same")
		#expect(notifications == 0)
	}

	@Test func dataFromTheActiveSessionIsHandled() async {
		let session = makeSession()
		let manager = makeManager(active: session)
		#expect(!wasHandled(by: session))
		await manager.didReceive(probeEvent(), from: session)
		#expect(wasHandled(by: session))
	}

	@Test func dataWithoutASessionStillGoesToTheActiveOne() async {
		let session = makeSession()
		let manager = makeManager(active: session)
		await manager.didReceive(probeEvent())
		#expect(wasHandled(by: session))
	}

	@Test func dataFromAStaleSessionIsDropped() async {
		let stale = makeSession(num: 0x0000_0001)
		let active = makeSession(num: 0x0000_0002)
		let manager = makeManager(active: active)
		await manager.didReceive(probeEvent(), from: stale)
		#expect(!wasHandled(by: stale))
		#expect(!wasHandled(by: active))
	}

	/// #2404: only a config completion a refresh owns proves the cached config is fresh, so one
	/// nothing waits on stamps neither the radio's session nor the manager.
	@Test func anUnownedConfigCompletionDoesNotStampTheRefresh() async {
		let session = makeSession()
		let manager = makeManager(active: session)
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .configCompleteID(12_345)
		await manager.didReceive(.data(fromRadio), from: session)
		#expect(manager.lastConfigRefresh == nil)
		#expect(session.lastConfigRefresh == nil)
	}

	@Test func rssiFromAStaleSessionDoesNotTouchTheActiveRadio() async {
		let active = makeSession()
		let manager = makeManager(active: active)
		await manager.didReceive(.rssiUpdate(-42), from: makeSession())
		#expect(active.device.rssi != -42)
		await manager.didReceive(.rssiUpdate(-42), from: active)
		#expect(active.device.rssi == -42)
	}
}
