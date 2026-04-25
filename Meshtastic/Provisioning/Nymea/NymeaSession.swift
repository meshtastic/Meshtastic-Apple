//
//  NymeaSession.swift
//  Meshtastic
//
//  Low-level BLE session implementing the nymea-networkmanager JSON-over-BLE protocol.
//
//  The nymea protocol uses two GATT services:
//    • Wireless Service  — scan networks, connect/disconnect Wi-Fi
//    • Network Service   — enable/disable networking & wireless adapter
//
//  All commands are sent as compact JSON ending with '\n', split into ≤20-byte BLE packets.
//  Responses arrive as notifications on the commander-response characteristic, also chunked
//  at 20 bytes and terminated by '\n'.
//
//  Protocol reference: https://github.com/nymea/nymea-networkmanager
//

import Foundation
@preconcurrency import CoreBluetooth
import OSLog

extension Logger {
	static let nymea = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Meshtastic", category: "NymeaSession")
}

// MARK: - Session Errors

enum NymeaSessionError: Error, LocalizedError {
	case notConnected
	case characteristicNotFound(String)
	case timeout
	case serviceDiscoveryFailed(Error)
	case invalidResponse
	case commandFailed(NymeaCommanderError)
	case networkCommandFailed(NymeaNetworkCommanderError)
	case wirelessConnectionFailed
	case noConnectionInfo

	var errorDescription: String? {
		switch self {
		case .notConnected:                      return "Not connected to device"
		case .characteristicNotFound(let name):  return "Required BLE characteristic not found: \(name)"
		case .timeout:                           return "Operation timed out"
		case .serviceDiscoveryFailed(let e):     return "Service discovery failed: \(e.localizedDescription)"
		case .invalidResponse:                   return "Received an invalid response from the device"
		case .commandFailed(let code):           return code.errorDescription ?? "Command failed"
		case .networkCommandFailed(let code):    return code.errorDescription ?? "Network command failed"
		case .wirelessConnectionFailed:          return "Device failed to connect to the Wi-Fi network"
		case .noConnectionInfo:                  return "Device did not return connection information"
		}
	}
}

// MARK: - NymeaSession

/// An `actor` that owns a single CoreBluetooth connection to a nymea-networkmanager device.
///
/// Callers interact with it via `async throws` methods.  The underlying CoreBluetooth delegate
/// bridge (`NymeaSessionDelegate`) forwards BLE notification callbacks into an `AsyncStream`
/// continuation synchronously (no `Task` wrapping), so the actor processes chunks in strict
/// FIFO order.  This prevents multi-chunk JSON frames from being reassembled out of order on
/// multi-core devices — a bug that would occur if each notification spawned its own `Task`.
///
/// Timeout pattern: each async operation spawns a detached `Task` that fires the actor-isolated
/// cancellation helper after a deadline; the outer `defer` cancels that task on normal completion.
/// This keeps the `withCheckedThrowingContinuation` body in the actor's isolation domain,
/// satisfying Swift 6 strict-concurrency rules.
actor NymeaSession {

	// MARK: Stored characteristics

	private var wirelessCommanderChar: CBCharacteristic?
	private var commanderResponseChar: CBCharacteristic?
	private var wirelessConnectionStatusChar: CBCharacteristic?
	private var wirelessModeChar: CBCharacteristic?
	private var networkStatusChar: CBCharacteristic?
	private var networkCommanderChar: CBCharacteristic?
	private var networkCommanderResponseChar: CBCharacteristic?
	private var networkingEnabledChar: CBCharacteristic?
	private var wirelessEnabledChar: CBCharacteristic?

	// MARK: State

	private let peripheral: CBPeripheral
	private let delegate: NymeaSessionDelegate

	/// Buffer for incoming notification bytes until we receive a full `\n`-terminated frame.
	private var responseBuffer = Data()

	/// Pending response continuations keyed by command code `"c"`.
	private var pendingCommandContinuations: [Int: CheckedContinuation<Data, Error>] = [:]

	/// Continuation for the service-discovery handshake.
	private var discoveryContinuation: CheckedContinuation<Void, Error>?

	/// Continuation for waiting on a network-service commander response byte.
	private var networkCommandContinuation: CheckedContinuation<UInt8, Error>?

	/// One-shot continuation for a `readValue` read of the wireless status characteristic.
	private var statusReadContinuation: CheckedContinuation<NymeaWirelessConnectionStatus, Error>?

	/// Stream for live wireless-status notifications (used while connecting).
	private var statusContinuation: AsyncStream<NymeaWirelessConnectionStatus>.Continuation?

	/// Whether service/characteristic discovery has completed.
	private var isReady = false

	// MARK: Notification delivery stream (ordered FIFO)

	/// A single notification event captured from CoreBluetooth.
	///
	/// We snapshot `characteristic.value` (and its `uuid`) at enqueue time rather
	/// than holding onto the `CBCharacteristic` reference. CoreBluetooth mutates
	/// `characteristic.value` in place each time a new notification arrives, so
	/// queuing the reference and reading `.value` later in `processNotifications()`
	/// would cause earlier queued items to read the bytes of *later* packets —
	/// producing duplicated/dropped chunks and garbled JSON frames.
	private struct NotificationEvent: Sendable {
		let uuid: CBUUID
		let value: Data?
		let error: Error?
	}

	/// The `nonisolated let` access level is intentional: `AsyncStream.Continuation` is
	/// `Sendable` and immutable after init, so it is safe to yield from outside the actor's
	/// isolation domain without going through the executor.  This is the key to guaranteeing
	/// that BLE notification chunks are processed in arrival order.
	private nonisolated let notificationContinuation: AsyncStream<NotificationEvent>.Continuation
	private let notificationStream: AsyncStream<NotificationEvent>

	// MARK: Init

	init(peripheral: CBPeripheral) {
		self.peripheral = peripheral

		// Build the ordered notification channel.  `AsyncStream.init` calls its closure
		// synchronously, so `notifCont` is guaranteed to be set before the next line.
		var notifCont: AsyncStream<NotificationEvent>.Continuation!
		self.notificationStream = AsyncStream { notifCont = $0 }
		self.notificationContinuation = notifCont

		self.delegate = NymeaSessionDelegate()
		self.delegate.setSession(self)
		peripheral.delegate = self.delegate

		// Kick off the single ordered processing loop.  Using `Task` here is fine because all
		// stored properties above are initialised, making `self` fully available.
		Task { await self.processNotifications() }
	}

	// MARK: - Notification ingestion (called synchronously from the delegate — no Task wrapper)

	/// Enqueue a BLE characteristic-value notification for ordered, actor-isolated processing.
	/// This method is `nonisolated` so the delegate can call it directly from the CoreBluetooth
	/// callback without hopping to the actor's executor.  Because `notificationContinuation` is
	/// a `Sendable` `let` constant, no shared mutable state is touched.
	///
	/// We snapshot `characteristic.value` here (rather than later in `processNotifications`)
	/// because CoreBluetooth reuses the same `CBCharacteristic` instance across notifications
	/// and overwrites its `.value` each time. Queuing only the reference would cause earlier
	/// items to be re-read with the latest packet's bytes.
	nonisolated func enqueueNotification(characteristic: CBCharacteristic, error: Error?) {
		let event = NotificationEvent(
			uuid: characteristic.uuid,
			value: characteristic.value,
			error: error
		)
		notificationContinuation.yield(event)
	}

	/// Drain the notification stream one item at a time, in order.
	private func processNotifications() async {
		for await event in notificationStream {
			handleCharacteristicUpdate(uuid: event.uuid, value: event.value, error: event.error)
		}
	}

	// MARK: - Public API

	/// Discover services and characteristics, then subscribe to notifications.
	/// Must be called before any other method.
	func connect(timeout: TimeInterval = 10) async throws {
		Logger.nymea.debug("🔧 Discovering nymea services on \(self.peripheral.name ?? "unknown", privacy: .public)")

		// Spawn a timeout task that resumes the continuation with an error if the deadline fires.
		let timeoutTask = Task { [weak self] in
			do {
				try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
				await self?.failDiscovery(with: NymeaSessionError.timeout)
			} catch { /* Task was cancelled — normal completion path */ }
		}
		defer { timeoutTask.cancel() }

		// withCheckedThrowingContinuation runs its closure synchronously in the current
		// actor context, so mutating actor-isolated properties here is valid.
		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			self.discoveryContinuation = cont
			self.peripheral.discoverServices([nymeaWirelessServiceUUID, nymeaNetworkServiceUUID])
		}

		isReady = true
		Logger.nymea.debug("🔧 Service discovery complete.")
	}

	/// Request a Wi-Fi network scan on the device.
	func scan() async throws {
		let cmd = NymeaSimpleCommand(command: .scan)
		try await sendAndAwaitResponse(command: cmd, commandCode: NymeaWirelessCommand.scan.rawValue)
	}

	/// Retrieve the list of visible Wi-Fi access points.
	func getNetworks() async throws -> [NymeaWifiNetwork] {
		let cmd = NymeaSimpleCommand(command: .getNetworks)
		let data = try await sendAndAwaitResponse(command: cmd, commandCode: NymeaWirelessCommand.getNetworks.rawValue)
		let response = try JSONDecoder().decode(NymeaGetNetworksResponse.self, from: data)
		if response.r != 0, let err = NymeaCommanderError(rawValue: response.r) {
			throw NymeaSessionError.commandFailed(err)
		}
		return response.p ?? []
	}

	/// Connect the device to a visible Wi-Fi network.
	func connectToNetwork(ssid: String, password: String) async throws {
		let params = NymeaConnectParams(e: ssid, p: password)
		let cmd = NymeaCommandPacket(command: .connect, params: params)
		try await sendAndAwaitResponse(command: cmd, commandCode: NymeaWirelessCommand.connect.rawValue)
	}

	/// Connect the device to a hidden (non-broadcasting) Wi-Fi network.
	func connectToHiddenNetwork(ssid: String, password: String) async throws {
		let params = NymeaConnectParams(e: ssid, p: password)
		let cmd = NymeaCommandPacket(command: .connectHidden, params: params)
		try await sendAndAwaitResponse(command: cmd, commandCode: NymeaWirelessCommand.connectHidden.rawValue)
	}

	/// Read the current Wi-Fi connection details (SSID, BSSID, signal, IP address).
	func getConnectionInfo() async throws -> NymeaWifiConnection {
		let cmd = NymeaSimpleCommand(command: .getConnection)
		let data = try await sendAndAwaitResponse(command: cmd, commandCode: NymeaWirelessCommand.getConnection.rawValue)
		let response = try JSONDecoder().decode(NymeaGetConnectionResponse.self, from: data)
		if response.r != 0, let err = NymeaCommanderError(rawValue: response.r) {
			throw NymeaSessionError.commandFailed(err)
		}
		guard let info = response.p else {
			throw NymeaSessionError.noConnectionInfo
		}
		return info
	}

	/// Enable networking on the device.
	func enableNetworking() async throws {
		try await writeNetworkCommand(.enableNetworking)
	}

	/// Enable wireless on the device.
	func enableWireless() async throws {
		try await writeNetworkCommand(.enableWireless)
	}

	/// Read the current one-byte wireless connection status from the device.
	func readWirelessStatus() async throws -> NymeaWirelessConnectionStatus {
		guard let char = wirelessConnectionStatusChar else {
			throw NymeaSessionError.characteristicNotFound("WirelessConnectionStatus")
		}

		let timeoutTask = Task { [weak self] in
			do {
				try await Task.sleep(nanoseconds: 5_000_000_000)
				await self?.failStatusRead(with: NymeaSessionError.timeout)
			} catch { /* cancelled */ }
		}
		defer { timeoutTask.cancel() }

		return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NymeaWirelessConnectionStatus, Error>) in
			self.statusReadContinuation = cont
			self.peripheral.readValue(for: char)
		}
	}

	/// Returns an `AsyncStream` that emits `NymeaWirelessConnectionStatus` values whenever the
	/// device notifies a connection-status change.  Subscribe before calling `connectToNetwork`.
	func wirelessStatusStream() -> AsyncStream<NymeaWirelessConnectionStatus> {
		AsyncStream { cont in
			statusContinuation = cont
			cont.onTermination = { _ in
				Task { await self.clearStatusContinuation() }
			}
		}
	}

	// MARK: - Delegate callbacks (called via Task { await } from NymeaSessionDelegate)
	// Note: handleCharacteristicUpdate is NOT called via Task — it is enqueued through
	// notificationContinuation and drained in order by processNotifications().

	func handleServicesDiscovered(error: Error?) {
		guard error == nil else {
			failDiscovery(with: NymeaSessionError.serviceDiscoveryFailed(error!))
			return
		}
		guard let services = peripheral.services, !services.isEmpty else {
			failDiscovery(with: NymeaSessionError.characteristicNotFound("No services found"))
			return
		}
		for service in services {
			peripheral.discoverCharacteristics(nil, for: service)
		}
	}

	func handleCharacteristicsDiscovered(for service: CBService, error: Error?) {
		if let error {
			failDiscovery(with: NymeaSessionError.serviceDiscoveryFailed(error))
			return
		}
		assignCharacteristics(for: service)
		if allRequiredCharacteristicsReady() {
			subscribeToNotifications()
			discoveryContinuation?.resume()
			discoveryContinuation = nil
		}
	}

	private func handleCharacteristicUpdate(uuid: CBUUID, value: Data?, error: Error?) {
		guard error == nil, let data = value else { return }

		switch uuid {
		case nymeaCommanderResponseUUID:
			handleResponseChunk(data)

		case nymeaWirelessConnectionStatusUUID:
			guard let byte = data.first,
				  let status = NymeaWirelessConnectionStatus(rawValue: byte) else { return }
			Logger.nymea.debug("🔧 Wireless status: \(status.description, privacy: .public)")
			if let cont = statusReadContinuation {
				cont.resume(returning: status)
				statusReadContinuation = nil
			} else {
				statusContinuation?.yield(status)
			}

		case nymeaNetworkCommanderResponseUUID:
			if let byte = data.first {
				networkCommandContinuation?.resume(returning: byte)
				networkCommandContinuation = nil
			}

		default:
			break
		}
	}

	// MARK: - Private timeout cancellation helpers (actor-isolated, called from timeout Tasks)

	private func failDiscovery(with error: Error) {
		discoveryContinuation?.resume(throwing: error)
		discoveryContinuation = nil
	}

	private func failCommand(code: Int, with error: Error) {
		pendingCommandContinuations.removeValue(forKey: code)?.resume(throwing: error)
	}

	private func failNetworkCommand(with error: Error) {
		networkCommandContinuation?.resume(throwing: error)
		networkCommandContinuation = nil
	}

	private func failStatusRead(with error: Error) {
		statusReadContinuation?.resume(throwing: error)
		statusReadContinuation = nil
	}

	// MARK: - Private stream helpers

	private func setStatusContinuation(_ cont: AsyncStream<NymeaWirelessConnectionStatus>.Continuation) {
		statusContinuation = cont
	}

	private func clearStatusContinuation() {
		statusContinuation = nil
	}

	// MARK: - JSON write + response correlation

	/// Encode `command` as compact JSON + `\n`, split into ≤20-byte packets, write each
	/// chunk to the wireless commander characteristic, then suspend until the matching response.
	@discardableResult
	private func sendAndAwaitResponse<T: Encodable>(
		command: T,
		commandCode: Int,
		timeout: TimeInterval = 15
	) async throws -> Data {
		guard let char = wirelessCommanderChar else {
			throw NymeaSessionError.characteristicNotFound("WirelessCommander")
		}
		guard isReady else { throw NymeaSessionError.notConnected }

		// Encode to compact JSON + newline frame delimiter
		var jsonData = try JSONEncoder().encode(command)
		jsonData.append(0x0A) // '\n'

		// Split into ≤20-byte BLE chunks (nymea protocol requirement).
		// The Wireless Commander characteristic declares Write With Response (0x08) only,
		// so each chunk must be a confirmed write.  CoreBluetooth queues them internally
		// and guarantees in-order delivery, so we do not need to await each ACK separately.
		let chunkSize = 20
		var offset = 0
		while offset < jsonData.count {
			let end = min(offset + chunkSize, jsonData.count)
			peripheral.writeValue(jsonData.subdata(in: offset..<end), for: char, type: .withResponse)
			offset += chunkSize
		}

		// Spawn a timeout task that cancels this command if it doesn't respond in time.
		let timeoutTask = Task { [weak self] in
			do {
				try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
				await self?.failCommand(code: commandCode, with: NymeaSessionError.timeout)
			} catch { /* cancelled */ }
		}
		defer { timeoutTask.cancel() }

		// Await the matching response — continuation is stored in the actor's isolated dict.
		return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
			self.pendingCommandContinuations[commandCode] = cont
		}
	}

	/// Buffer incoming notification bytes and dispatch complete `\n`-terminated JSON frames.
	private func handleResponseChunk(_ chunk: Data) {
		responseBuffer.append(chunk)
		while let newlineIdx = responseBuffer.firstIndex(of: 0x0A) {
			let frameData = responseBuffer.prefix(upTo: newlineIdx)
			responseBuffer.removeSubrange(responseBuffer.startIndex...newlineIdx)
			guard !frameData.isEmpty else { continue }

			if let packet = try? JSONDecoder().decode(NymeaResponsePacket.self, from: frameData) {
				Logger.nymea.debug("🔧 Response: cmd=\(packet.c) result=\(packet.r)")
				if let cont = pendingCommandContinuations.removeValue(forKey: packet.c) {
					if packet.r == 0 {
						cont.resume(returning: frameData)
					} else if let err = NymeaCommanderError(rawValue: packet.r) {
						cont.resume(throwing: NymeaSessionError.commandFailed(err))
					} else {
						cont.resume(throwing: NymeaSessionError.invalidResponse)
					}
				}
			} else {
				let raw = String(data: frameData, encoding: .utf8)
					?? frameData.map { String(format: "%02x", $0) }.joined(separator: " ")
				Logger.nymea.error("🔧 Could not decode response JSON frame: \(raw, privacy: .public)")
			}
		}
	}

	// MARK: - Network Service command

	/// Write a single-byte command to the Network Service commander and await the 1-byte response.
	private func writeNetworkCommand(_ command: NymeaNetworkCommand, timeout: TimeInterval = 5) async throws {
		guard let char = networkCommanderChar else {
			throw NymeaSessionError.characteristicNotFound("NetworkCommander")
		}

		let timeoutTask = Task { [weak self] in
			do {
				try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
				await self?.failNetworkCommand(with: NymeaSessionError.timeout)
			} catch { /* cancelled */ }
		}
		defer { timeoutTask.cancel() }

		let result: UInt8 = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt8, Error>) in
			self.networkCommandContinuation = cont
			self.peripheral.writeValue(Data([command.rawValue]), for: char, type: .withResponse)
		}

		if result != 0, let err = NymeaNetworkCommanderError(rawValue: result) {
			throw NymeaSessionError.networkCommandFailed(err)
		}
	}

	// MARK: - Characteristic assignment helpers

	private func assignCharacteristics(for service: CBService) {
		for char in service.characteristics ?? [] {
			switch char.uuid {
			case nymeaWirelessCommanderUUID:        wirelessCommanderChar = char
			case nymeaCommanderResponseUUID:        commanderResponseChar = char
			case nymeaWirelessConnectionStatusUUID: wirelessConnectionStatusChar = char
			case nymeaWirelessModeUUID:             wirelessModeChar = char
			case nymeaNetworkStatusUUID:            networkStatusChar = char
			case nymeaNetworkCommanderUUID:         networkCommanderChar = char
			case nymeaNetworkCommanderResponseUUID: networkCommanderResponseChar = char
			case nymeaNetworkingEnabledUUID:        networkingEnabledChar = char
			case nymeaWirelessEnabledUUID:          wirelessEnabledChar = char
			default:                                break
			}
		}
	}

	/// Returns `true` once all essential wireless-service characteristics are present.
	private func allRequiredCharacteristicsReady() -> Bool {
		wirelessCommanderChar != nil &&
		commanderResponseChar != nil &&
		wirelessConnectionStatusChar != nil &&
		networkCommanderChar != nil
	}

	private func subscribeToNotifications() {
		for char in [commanderResponseChar, wirelessConnectionStatusChar, networkCommanderResponseChar] {
			if let char { peripheral.setNotifyValue(true, for: char) }
		}
	}
}

// MARK: - CoreBluetooth Delegate Bridge

/// An `NSObject` that receives CoreBluetooth callbacks and bridges them to `NymeaSession`.
///
/// - Discovery callbacks (`didDiscoverServices`, `didDiscoverCharacteristicsFor`) are forwarded
///   via `Task { await … }` because they are one-time events where ordering between separate
///   service objects is not critical.
/// - Value-update notifications (`didUpdateValueFor`) are forwarded **synchronously** via
///   `enqueueNotification` — no `Task` wrapper — to preserve strict chunk arrival order in
///   the actor's `AsyncStream` processing loop.
final class NymeaSessionDelegate: NSObject, CBPeripheralDelegate, @unchecked Sendable {

	private weak var session: NymeaSession?

	func setSession(_ s: NymeaSession) { session = s }

	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		Task { await session?.handleServicesDiscovered(error: error) }
	}

	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		Task { await session?.handleCharacteristicsDiscovered(for: service, error: error) }
	}

	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		// Call directly — no Task wrapper — so chunks are enqueued in strict arrival order.
		session?.enqueueNotification(characteristic: characteristic, error: error)
	}

	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		if let error {
			Logger.nymea.error("🔧 Notification subscribe failed for \(characteristic.uuid): \(error.localizedDescription, privacy: .public)")
		}
	}

	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		if let error {
			Logger.nymea.error("🔧 Write failed for \(characteristic.uuid): \(error.localizedDescription, privacy: .public)")
		}
	}
}
