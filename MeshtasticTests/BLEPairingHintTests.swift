//
//  BLEPairingHintTests.swift
//  MeshtasticTests
//
//  Covers the pure-logic pieces of the issue #2057 fix (custom-PIN BLE pairing sheet
//  auto-dismissing): the persisted paired-peripheral hint used to pick the connect
//  timeout, and the classification of notify-state errors into pairing failures vs.
//  benign per-characteristic errors.
//

import Foundation
import CoreBluetooth
import MeshtasticProtobufs
import Testing

@testable import Meshtastic

// Serialized: these tests share global UserDefaults state (`pairedPeripheralIds`),
// so they must not run in parallel with each other.
@MainActor
@Suite("Paired peripheral hint", .serialized)
final class PairedPeripheralHintTests {

	private let idA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
	private let idB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

	/// Snapshot of the real persisted values, captured before each test and restored in `deinit`
	/// so this suite leaves no residue for later tests to observe.
	private let originalPairedIds: [String]
	private let originalPreferredId: String
	private let originalPurgeStaleNodeDays: Double
	private let originalAutoconnect: Bool
	private let originalMigratedPairing: Bool

	/// Swift Testing creates a fresh instance per test, so `init`/`deinit` act as per-test
	/// setup/teardown: start every test from a clean slate, then restore the original value.
	init() {
		originalPairedIds = UserDefaults.pairedPeripheralIds
		originalPreferredId = UserDefaults.preferredPeripheralId
		originalPurgeStaleNodeDays = UserDefaults.purgeStaleNodeDays
		originalAutoconnect = UserDefaults.autoconnectOnDiscovery
		originalMigratedPairing = UserDefaults.migratedPreferredPeripheralPairing
		UserDefaults.pairedPeripheralIds = []
		UserDefaults.preferredPeripheralId = ""
		UserDefaults.autoconnectOnDiscovery = true
		UserDefaults.migratedPreferredPeripheralPairing = true
	}

	deinit {
		UserDefaults.pairedPeripheralIds = originalPairedIds
		UserDefaults.preferredPeripheralId = originalPreferredId
		UserDefaults.purgeStaleNodeDays = originalPurgeStaleNodeDays
		UserDefaults.autoconnectOnDiscovery = originalAutoconnect
		UserDefaults.migratedPreferredPeripheralPairing = originalMigratedPairing
	}

	@Test func rememberMakesPeripheralKnown() {
		#expect(UserDefaults.isPairedPeripheral(idA) == false)

		UserDefaults.rememberPairedPeripheral(idA)

		#expect(UserDefaults.isPairedPeripheral(idA))
		#expect(UserDefaults.isPairedPeripheral(idB) == false)
	}

	@Test func rememberIsIdempotent() {
		UserDefaults.rememberPairedPeripheral(idA)
		UserDefaults.rememberPairedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idA.uuidString])
	}

	@Test func forgetRemovesOnlyThatPeripheral() {
		UserDefaults.rememberPairedPeripheral(idA)
		UserDefaults.rememberPairedPeripheral(idB)

		UserDefaults.forgetPairedPeripheral(idA)

		#expect(UserDefaults.isPairedPeripheral(idA) == false)
		#expect(UserDefaults.isPairedPeripheral(idB))
	}

	@Test func forgetUnknownPeripheralIsNoOp() {
		UserDefaults.rememberPairedPeripheral(idB)

		UserDefaults.forgetPairedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idB.uuidString])
	}

	@Test func invalidationRemovesPairingHintAndMatchingPreference() {
		UserDefaults.pairedPeripheralIds = [idA.uuidString, idB.uuidString]
		UserDefaults.preferredPeripheralId = idA.uuidString

		UserDefaults.invalidateSavedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idB.uuidString])
		#expect(UserDefaults.preferredPeripheralId.isEmpty)
	}

	@Test func invalidationDoesNotClearDifferentPreference() {
		UserDefaults.pairedPeripheralIds = [idA.uuidString, idB.uuidString]
		UserDefaults.preferredPeripheralId = idB.uuidString

		UserDefaults.invalidateSavedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idB.uuidString])
		#expect(UserDefaults.preferredPeripheralId == idB.uuidString)
	}

	@Test func invalidationIsIdempotent() {
		UserDefaults.pairedPeripheralIds = [idA.uuidString]
		UserDefaults.preferredPeripheralId = idA.uuidString

		UserDefaults.invalidateSavedPeripheral(idA)
		UserDefaults.invalidateSavedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds.isEmpty)
		#expect(UserDefaults.preferredPeripheralId.isEmpty)
	}

	@Test func forgetSavedRadioWorksWithoutADiscoveredDevice() {
		UserDefaults.pairedPeripheralIds = [idA.uuidString]
		UserDefaults.preferredPeripheralId = idA.uuidString
		UserDefaults.purgeStaleNodeDays = 30

		UserDefaults.forgetSavedRadio()

		#expect(UserDefaults.pairedPeripheralIds.isEmpty)
		#expect(UserDefaults.preferredPeripheralId.isEmpty)
		#expect(UserDefaults.purgeStaleNodeDays == 30)
	}

	@Test func storedIdsAreSorted() {
		UserDefaults.rememberPairedPeripheral(idB)
		UserDefaults.rememberPairedPeripheral(idA)

		#expect(UserDefaults.pairedPeripheralIds == [idA.uuidString, idB.uuidString].sorted())
	}

	private func device(id: UUID) -> Device {
		Device(
			id: id,
			name: "Test Radio",
			transportType: .ble,
			identifier: "test-radio",
			connectionState: .disconnected
		)
	}

	@Test func rediscoveryDoesNotAutoconnectAfterInvalidation() {
		let manager = AccessoryManager(transports: [])
		let failedDevice = device(id: idA)
		UserDefaults.pairedPeripheralIds = [idA.uuidString]
		UserDefaults.preferredPeripheralId = idA.uuidString
		#expect(manager.shouldAutomaticallyConnect(to: failedDevice))

		UserDefaults.invalidateSavedPeripheral(idA)

		#expect(manager.shouldAutomaticallyConnect(to: failedDevice) == false)
		#expect(UserDefaults.autoconnectOnDiscovery)
	}

	@Test func invalidatingFailedRadioPreservesAutoconnectForNewSelection() {
		let manager = AccessoryManager(transports: [])
		let newlySelectedDevice = device(id: idB)
		UserDefaults.pairedPeripheralIds = [idA.uuidString, idB.uuidString]
		UserDefaults.preferredPeripheralId = idB.uuidString

		UserDefaults.invalidateSavedPeripheral(idA)

		#expect(manager.shouldAutomaticallyConnect(to: newlySelectedDevice))
		#expect(UserDefaults.autoconnectOnDiscovery)
	}

	@Test func terminalPairingFailureStopsRetryAllAndInvalidatesSavedRadio() async throws {
		let connection = PairingFailureTestConnection(failure: .terminalPairing)
		let manager = AccessoryManager(transports: [PairingFailureTestTransport()])
		manager.isSwitchingDevices = true
		UserDefaults.pairedPeripheralIds = [idA.uuidString]
		UserDefaults.preferredPeripheralId = idA.uuidString

		try await manager.connect(
			to: device(id: idA),
			withConnection: connection,
			wantConfig: false,
			wantDatabase: false,
			versionCheck: false
		)

		#expect(await connection.connectCallCount == 1)
		#expect(UserDefaults.pairedPeripheralIds.isEmpty)
		#expect(UserDefaults.preferredPeripheralId.isEmpty)
		#expect(manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError)
		let surfacedError = try #require(manager.lastConnectionError as? AccessoryError)
		guard case .coreBluetoothATTError(let error) = surfacedError else {
			Issue.record("Expected a surfaced Bluetooth pairing error")
			return
		}
		#expect(error.code == .insufficientAuthentication)
	}

	@Test(arguments: [
		PairingFailureTestConnection.Failure.timeout,
		.peripheralDisconnected,
		.encryptionTimedOut,
		.insufficientEncryption,
		.insufficientAuthorization
	])
	func ambiguousFailureKeepsSavedRadioButSuppressesSameSessionRediscoveryAfterRetries(
		_ failure: PairingFailureTestConnection.Failure
	) async throws {
		let connection = PairingFailureTestConnection(failure: failure)
		let manager = AccessoryManager(transports: [PairingFailureTestTransport()])
		manager.isSwitchingDevices = true
		let savedDevice = device(id: idA)
		UserDefaults.pairedPeripheralIds = [idA.uuidString]
		UserDefaults.preferredPeripheralId = idA.uuidString

		try await manager.connect(
			to: savedDevice,
			withConnection: connection,
			wantConfig: false,
			wantDatabase: false,
			versionCheck: false
		)

		#expect(await connection.connectCallCount == 2)
		#expect(UserDefaults.pairedPeripheralIds == [idA.uuidString])
		#expect(UserDefaults.preferredPeripheralId == idA.uuidString)
		#expect(UserDefaults.autoconnectOnDiscovery)
		#expect(manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError == false)
		manager.isSwitchingDevices = false
		#expect(manager.shouldAutomaticallyConnect(to: savedDevice) == false)

		let nextSessionManager = AccessoryManager(transports: [])
		#expect(nextSessionManager.shouldAutomaticallyConnect(to: savedDevice))
	}

	@Test func validSavedRadioRemainsEligibleForReconnect() {
		let manager = AccessoryManager(transports: [])
		let savedDevice = device(id: idA)
		UserDefaults.pairedPeripheralIds = [idA.uuidString]
		UserDefaults.preferredPeripheralId = idA.uuidString

		#expect(UserDefaults.isPairedPeripheral(idA))
		#expect(manager.shouldAutomaticallyConnect(to: savedDevice))
	}
}

@Suite("BLE pairing failure classification")
struct BLEPairingFailureTests {

	@Test func authAndEncryptionAttErrorsArePairingFailures() {
		#expect(BLEConnection.isPairingFailure(CBATTError(.insufficientAuthentication)))
		#expect(BLEConnection.isPairingFailure(CBATTError(.insufficientEncryption)))
		#expect(BLEConnection.isPairingFailure(CBATTError(.insufficientAuthorization)))
	}

	@Test func benignAttErrorsAreNotPairingFailures() {
		// e.g. a characteristic that doesn't support notifications — must not fail an
		// otherwise-good connect.
		#expect(BLEConnection.isPairingFailure(CBATTError(.writeNotPermitted)) == false)
		#expect(BLEConnection.isPairingFailure(CBATTError(.requestNotSupported)) == false)
	}

	@Test func encryptionAndRemovedPairingCbErrorsArePairingFailures() {
		#expect(BLEConnection.isPairingFailure(CBError(.encryptionTimedOut)))
		#expect(BLEConnection.isPairingFailure(CBError(.peerRemovedPairingInformation)))
	}

	@Test func staleBondFailuresAreTerminalForSavedRadioInvalidation() {
		#expect(BLEConnection.isTerminalSavedRadioPairingFailure(CBATTError(.insufficientAuthentication)))
		#expect(BLEConnection.isTerminalSavedRadioPairingFailure(CBError(.peerRemovedPairingInformation)))
	}

	@Test func ambiguousPairingFailuresPreserveSavedRadio() {
		#expect(BLEConnection.isTerminalSavedRadioPairingFailure(CBATTError(.insufficientEncryption)) == false)
		#expect(BLEConnection.isTerminalSavedRadioPairingFailure(CBATTError(.insufficientAuthorization)) == false)
		#expect(BLEConnection.isTerminalSavedRadioPairingFailure(CBError(.encryptionTimedOut)) == false)
	}

	@Test func unrelatedCbErrorsAreNotPairingFailures() {
		#expect(BLEConnection.isPairingFailure(CBError(.connectionTimeout)) == false)
		#expect(BLEConnection.isPairingFailure(CBError(.peripheralDisconnected)) == false)
	}

	@Test func genericErrorsAreNotPairingFailures() {
		let generic = NSError(domain: "com.example.test", code: 42)
		#expect(BLEConnection.isPairingFailure(generic) == false)
	}
}

private struct PairingFailureTestTransport: Transport {
	let type: TransportType = .ble
	var status: TransportStatus { get async { .ready } }
	let requiresPeriodicHeartbeat = false
	let supportsManualConnection = false

	func discoverDevices() async -> AsyncStream<DiscoveryEvent> {
		AsyncStream { $0.finish() }
	}

	func connect(to device: Device) async throws -> any Connection {
		throw NSError(domain: "PairingFailureTestTransport", code: 1)
	}

	func device(forManualConnection: String) -> Device? { nil }
	func manuallyConnect(toDevice: Device) async throws {}
}

actor PairingFailureTestConnection: Connection {
	enum Failure {
		case terminalPairing
		case timeout
		case peripheralDisconnected
		case encryptionTimedOut
		case insufficientEncryption
		case insufficientAuthorization
	}

	let type: TransportType = .ble
	let failure: Failure
	private(set) var connectCallCount = 0
	var isConnected: Bool { false }

	init(failure: Failure) {
		self.failure = failure
	}

	func send(_ data: ToRadio) async throws {}

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		connectCallCount += 1
		switch failure {
		case .terminalPairing:
			throw CBATTError(.insufficientAuthentication)
		case .timeout:
			throw CBError(.connectionTimeout)
		case .peripheralDisconnected:
			throw CBError(.peripheralDisconnected)
		case .encryptionTimedOut:
			throw CBError(.encryptionTimedOut)
		case .insufficientEncryption:
			throw CBATTError(.insufficientEncryption)
		case .insufficientAuthorization:
			throw CBATTError(.insufficientAuthorization)
		}
	}

	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {}
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}
