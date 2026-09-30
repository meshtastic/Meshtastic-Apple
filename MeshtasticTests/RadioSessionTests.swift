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

	/// A config-complete with a nonce nothing waits on: it only stamps `lastConfigRefresh`, which
	/// makes it a side-effect-free probe of whether a data event was handled.
	private func probeEvent() -> ConnectionEvent {
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .configCompleteID(12_345)
		return .data(fromRadio)
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
		#expect(manager.lastConfigRefresh == nil)
		await manager.didReceive(probeEvent(), from: session)
		#expect(manager.lastConfigRefresh != nil)
	}

	@Test func dataWithoutASessionStillGoesToTheActiveOne() async {
		let manager = makeManager(active: makeSession())
		await manager.didReceive(probeEvent())
		#expect(manager.lastConfigRefresh != nil)
	}

	@Test func dataFromAStaleSessionIsDropped() async {
		let stale = makeSession(num: 0x0000_0001)
		let manager = makeManager(active: makeSession(num: 0x0000_0002))
		await manager.didReceive(probeEvent(), from: stale)
		#expect(manager.lastConfigRefresh == nil)
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
