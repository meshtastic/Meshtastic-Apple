// MARK: BLETransportCentralManagerOptionsTests
//
//  BLETransportCentralManagerOptionsTests.swift
//  MeshtasticTests
//
//  Covers the fix for issue #2139: the app initializes BLE discovery unconditionally on
//  every launch (AccessoryManager.startDiscovery() fans out to every transport, regardless
//  of which one the user actually connects with), so a TCP/WiFi-only user with Bluetooth
//  off on the device was seeing the system "Bluetooth is turned off" alert every launch —
//  and, because presenting that alert blips scenePhase and appDidBecomeActive() re-arms BLE
//  discovery, in a tight dismiss/reappear loop.
//
//  These tests pin down the options CBCentralManager is created with (BLETransport.
//  centralManagerOptions), since that's the only piece of the fix that's cheaply testable
//  without standing up a real CoreBluetooth stack.
//

import CoreBluetooth
import Testing

@testable import Meshtastic

@Suite("BLETransport central manager options")
struct BLETransportCentralManagerOptionsTests {

	@Test func suppressesTheSystemPowerAlert() {
		let options = BLETransport.centralManagerOptions(restoreIdentifier: "com.meshtastic.central")

		let showPowerAlert = options[CBCentralManagerOptionShowPowerAlertKey] as? Bool
		#expect(showPowerAlert == false, "CBCentralManagerOptionShowPowerAlertKey must be false, or the system 'Bluetooth is turned off' alert reappears every launch for TCP/WiFi-only users (#2139)")
	}

	@Test func preservesStateRestoration() {
		let restoreId = "com.meshtastic.central"
		let options = BLETransport.centralManagerOptions(restoreIdentifier: restoreId)

		let restoredIdentifier = options[CBCentralManagerOptionRestoreIdentifierKey] as? String
		#expect(restoredIdentifier == restoreId, "Suppressing the power alert must not disable state restoration for backgrounded BLE connections")
	}

	@Test func passesThroughTheGivenRestoreIdentifier() {
		let options = BLETransport.centralManagerOptions(restoreIdentifier: "some-other-id")

		let restoredIdentifier = options[CBCentralManagerOptionRestoreIdentifierKey] as? String
		#expect(restoredIdentifier == "some-other-id")
	}

	@Test func containsExactlyTheExpectedKeys() {
		let options = BLETransport.centralManagerOptions(restoreIdentifier: "com.meshtastic.central")

		#expect(Set(options.keys) == Set([CBCentralManagerOptionRestoreIdentifierKey, CBCentralManagerOptionShowPowerAlertKey]))
	}
}
