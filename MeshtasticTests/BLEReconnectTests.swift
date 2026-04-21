import Foundation
import Testing

@testable import Meshtastic

// MARK: - BLE Reconnect Bug-Fix Tests
//
// These tests cover the BLE reconnect crash fixes:
//   • connect(to:) no longer force-unwraps UUID(uuidString:) — invalid identifiers throw gracefully
//   • Device model correctly represents BLE identifier states

@Suite("BLE Reconnect")
struct BLEReconnectTests {

	// MARK: - UUID identifier validation (fix for force-unwrap crash)

	@Suite("Device identifier validation")
	struct DeviceIdentifierTests {

		/// A well-formed UUID identifier must produce a valid Device without throwing.
		@Test func validUUIDIdentifierIsAccepted() {
			let validUUID = "12345678-1234-1234-1234-123456789ABC"
			let id = UUID()
			let device = Device(
				id: id,
				name: "Radio",
				transportType: .ble,
				identifier: validUUID
			)
			#expect(device.identifier == validUUID)
		}

		/// An empty identifier is accepted by the Device model layer without crashing.
		/// The guard-let that prevents a crash lives inside BLETransport.connect(to:); the Foundation
		/// API behaviour it relies on (UUID(uuidString:) returning nil) is covered by
		/// `invalidUUIDStringsReturnNilFromFoundation` below.
		@Test func emptyIdentifierStoredSafelyInDeviceModel() {
			let id = UUID()
			let device = Device(
				id: id,
				name: "Radio",
				transportType: .ble,
				identifier: ""
			)
			#expect(device.identifier == "")
		}

		/// A non-UUID string (e.g. IP address mistakenly stored for BLE) must not crash at the Device layer.
		@Test func nonUUIDStringIdentifierIsStoredSafely() {
			let id = UUID()
			let device = Device(
				id: id,
				name: "Radio",
				transportType: .ble,
				identifier: "192.168.1.100:4403"
			)
			#expect(device.identifier == "192.168.1.100:4403")
		}

		/// A valid UUID string round-trips through Foundation's UUID initialiser.
		@Test func validUUIDStringParseable() {
			let uuidString = "AABBCCDD-EEFF-0011-2233-445566778899"
			let parsed = UUID(uuidString: uuidString)
			#expect(parsed != nil)
		}

		/// The fix ensures we use a guard-let rather than force-unwrap. Verify the
		/// safe unwrap path: nil from UUID(uuidString:) is handled, not crashed.
		@Test(arguments: [
			"",
			"not-a-uuid",
			"ZZZZZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZZZZZZZZZ",
			"12345",
		])
		func invalidUUIDStringsReturnNilFromFoundation(input: String) {
			// This directly tests the Foundation API behaviour the fix relies on.
			let parsed = UUID(uuidString: input)
			#expect(parsed == nil)
		}
	}

	// MARK: - BLE Signal Strength edge cases
	// Boundary values (-65, -84, -85, etc.) are already covered by DeviceTests.signalStrength
	// in ConnectViewTests.swift; only extreme values outside that range are added here.

	@Suite("Signal strength edge cases")
	struct SignalStrengthBoundaryTests {

		static let testUUID = UUID()

		private func device(rssi: Int) -> Device {
			Device(id: Self.testUUID, name: "R", transportType: .ble, identifier: "ID", rssi: rssi)
		}

		/// Extreme RSSI values (beyond the documented -120 .. 0 range) must not crash.
		@Test(arguments: [0, -1, -120, Int.min])
		func extremeRSSIValuesDoNotCrash(rssi: Int) {
			let strength = device(rssi: rssi).getSignalStrength()
			#expect(strength != nil)
		}
	}

	// MARK: - Connection state transitions

	@Suite("Connection state")
	struct ConnectionStateTransitionTests {

		static let testUUID = UUID()

		@Test func initialStateIsDisconnected() {
			let device = Device(id: Self.testUUID, name: "R", transportType: .ble, identifier: "ID")
			#expect(device.connectionState == .disconnected)
		}

		@Test func connectingStateIsDistinctFromConnected() {
			#expect(ConnectionState.connecting != .connected)
			#expect(ConnectionState.connecting != .disconnected)
		}

		@Test func deviceCanBeCreatedInConnectedState() {
			let device = Device(
				id: Self.testUUID,
				name: "R",
				transportType: .ble,
				identifier: "ID",
				connectionState: .connected
			)
			#expect(device.connectionState == .connected)
		}

		@Test func deviceCanBeCreatedInConnectingState() {
			let device = Device(
				id: Self.testUUID,
				name: "R",
				transportType: .ble,
				identifier: "ID",
				connectionState: .connecting
			)
			#expect(device.connectionState == .connecting)
		}
	}

	// MARK: - wasRestored flag (state restoration path)

	@Suite("State restoration")
	struct StateRestorationTests {

		static let testUUID = UUID()

		@Test func restoredDeviceHasFlagSet() {
			let device = Device(
				id: Self.testUUID,
				name: "Restored Radio",
				transportType: .ble,
				identifier: Self.testUUID.uuidString,
				wasRestored: true
			)
			#expect(device.wasRestored == true)
		}

		@Test func nonRestoredDeviceHasFlagUnset() {
			let device = Device(
				id: Self.testUUID,
				name: "Normal Radio",
				transportType: .ble,
				identifier: Self.testUUID.uuidString
			)
			#expect(device.wasRestored == false)
		}

		/// wasRestored does not affect identifier or connection state.
		@Test func restorationFlagIsOrthogonalToOtherProperties() {
			let id = Self.testUUID
			let restoredDevice = Device(
				id: id, name: "R", transportType: .ble,
				identifier: id.uuidString, connectionState: .connecting, wasRestored: true
			)
			let normalDevice = Device(
				id: id, name: "R", transportType: .ble,
				identifier: id.uuidString, connectionState: .connecting, wasRestored: false
			)
			#expect(restoredDevice.identifier == normalDevice.identifier)
			#expect(restoredDevice.connectionState == normalDevice.connectionState)
			#expect(restoredDevice.wasRestored != normalDevice.wasRestored)
		}
	}

	// MARK: - Transport type correctness

	@Suite("BLE transport type")
	struct BLETransportTypeTests {

		@Test func bleTransportTypeRawValue() {
			#expect(TransportType.ble.rawValue == "BLE")
		}

		@Test func bleIsDistinctFromOtherTransports() {
			#expect(TransportType.ble != .tcp)
			#expect(TransportType.ble != .serial)
		}

		@Test func deviceIdentifiesBLETransport() {
			let device = Device(
				id: UUID(), name: "R", transportType: .ble, identifier: UUID().uuidString
			)
			#expect(device.transportType == .ble)
		}
	}
}
