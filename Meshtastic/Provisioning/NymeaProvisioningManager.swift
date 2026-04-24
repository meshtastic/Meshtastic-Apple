//
//  NymeaProvisioningManager.swift
//  Meshtastic
//
//  Orchestrates Wi-Fi provisioning for mPWRD-OS devices running nymea-networkmanager.
//
//  NOTE: AccessorySetupKit cannot be used alongside a global CBCentralManager created
//  via NSBluetoothAlwaysUsageDescription (ASK's showPicker throws "CBManagers active
//  with global permissions"). Meshtastic must keep its global BLE access for Meshtastic
//  radio connectivity, so this manager uses a dedicated CBCentralManager with a custom
//  device-picker UI instead.
//

import Foundation
@preconcurrency import CoreBluetooth
import OSLog

// MARK: - Discovered Device

/// A nymea-networkmanager peripheral found during the provisioning BLE scan.
struct NymeaDiscoveredDevice: Identifiable, @unchecked Sendable {
	/// `CBPeripheral.identifier`
	let id: UUID
	/// Advertised name, defaulting to "mPWRD-OS" when absent.
	let name: String
	let peripheral: CBPeripheral
	var rssi: Int
	var lastSeen: Date
}

extension NymeaDiscoveredDevice: Equatable {
	static func == (lhs: NymeaDiscoveredDevice, rhs: NymeaDiscoveredDevice) -> Bool {
		lhs.id == rhs.id
	}
}

// MARK: - Provisioning State

enum ProvisioningState: Equatable {
	/// No active session.
	case idle
	/// BLE scan running; no devices found yet.
	case scanningForDevices
	/// At least one device found — showing the device picker.
	case selectingDevice([NymeaDiscoveredDevice])
	/// User picked a device; establishing the BLE connection.
	case connectingBLE
	/// Connected; ensuring NetworkManager has networking and wireless enabled.
	case checkingNetworkState
	/// Requesting a Wi-Fi network scan on the device.
	case scanning
	/// Scan complete — showing the network list to the user.
	case awaitingNetworkSelection([NymeaWifiNetwork])
	/// Credentials sent; device is associating with the AP.
	case sendingCredentials(ssid: String)
	/// Device connected; reading assigned IP address.
	case retrievingIPAddress
	/// Provisioning complete.
	case success(ipAddress: String)
	/// Terminal error.
	case failed(String)

	static func == (lhs: ProvisioningState, rhs: ProvisioningState) -> Bool {
		switch (lhs, rhs) {
		case (.idle, .idle),
			 (.scanningForDevices, .scanningForDevices),
			 (.connectingBLE, .connectingBLE),
			 (.checkingNetworkState, .checkingNetworkState),
			 (.scanning, .scanning),
			 (.retrievingIPAddress, .retrievingIPAddress):
			return true
		case (.selectingDevice(let a), .selectingDevice(let b)): return a == b
		case (.sendingCredentials(let a), .sendingCredentials(let b)): return a == b
		case (.success(let a), .success(let b)): return a == b
		case (.failed(let a), .failed(let b)): return a == b
		default: return false
		}
	}
}

// MARK: - NymeaProvisioningManager

@MainActor
final class NymeaProvisioningManager: NSObject, ObservableObject {

	static let shared = NymeaProvisioningManager()

	@Published private(set) var state: ProvisioningState = .idle

	/// Devices currently visible to the passive (background) scan. Updated whenever a
	/// scan is running — passive or active — so the Connect view can list nearby
	/// nymea devices even before the user opens the provisioning sheet.
	@Published private(set) var discoverable: [NymeaDiscoveredDevice] = []

	// MARK: Scanning

	private enum ScanMode {
		/// Background scan driven by the Connect view; updates `discoverable` only.
		case passive
		/// Active scan during a user-initiated provisioning session; also drives
		/// `state` transitions (`.scanningForDevices` / `.selectingDevice`).
		case active
	}

	private var central: CBCentralManager?
	private var centralDelegate: NymeaCentralDelegate?
	private var scanMode: ScanMode = .passive
	/// Devices seen during the current scan, keyed by peripheral identifier.
	private var discoveredDevices: [UUID: NymeaDiscoveredDevice] = [:]
	private var cleanupTask: Task<Void, Never>?

	// MARK: Session

	private var targetPeripheral: CBPeripheral?
	private var nymeaSession: NymeaSession?
	private var provisioningTask: Task<Void, Never>?

	private override init() { super.init() }

	// MARK: - Public API

	/// Begin scanning for nearby mPWRD-OS devices.
	func startProvisioning() {
		guard state == .idle else { return }
		transition(to: .scanningForDevices)
		startScanning(mode: .active)
	}

	/// Begin a provisioning session against an already-discovered device, skipping
	/// the in-sheet scan/picker steps. Used when the user taps a nymea device from
	/// the Connect list.
	func beginProvisioning(with device: NymeaDiscoveredDevice) {
		guard state == .idle else { return }
		// IMPORTANT: claim the target peripheral and transition state BEFORE calling
		// stopScanning(). stopScanning() releases the CBCentralManager when
		// `state == .idle && targetPeripheral == nil`, and we need to keep the
		// central alive to issue the connect() below.
		scanMode = .active
		targetPeripheral = device.peripheral
		transition(to: .connectingBLE)
		// Tear down the passive discovery scan (without releasing the central).
		central?.stopScan()
		cleanupTask?.cancel()
		cleanupTask = nil
		discoveredDevices.removeAll()
		discoverable = []
		// We need a CBCentralManager to call connect(). Reuse the existing passive
		// central if present; otherwise stand up a fresh one.
		if central == nil {
			let delegate = NymeaCentralDelegate()
			delegate.manager = self
			centralDelegate = delegate
			central = CBCentralManager(delegate: delegate, queue: .main)
		}
		// If the central is already powered on we can connect immediately; otherwise
		// the connection will be issued from centralDidBecomeReady once it's ready.
		if central?.state == .poweredOn {
			central?.connect(device.peripheral)
		}
	}

	/// Start a passive background scan that publishes discovered nymea devices via
	/// `discoverable` without altering `state`. No-op while a provisioning session
	/// is in flight.
	func startDiscovery() {
		guard state == .idle else { return }
		guard central == nil else { return } // already scanning
		startScanning(mode: .passive)
	}

	/// Stop the passive background scan. No-op if a provisioning session is active.
	func stopDiscovery() {
		guard state == .idle else { return }
		stopScanning()
	}

	/// Connect to the user-selected device and begin the provisioning flow.
	func selectDevice(_ device: NymeaDiscoveredDevice) {
		guard case .selectingDevice = state else { return }
		stopScanning()
		transition(to: .connectingBLE)
		targetPeripheral = device.peripheral
		central?.connect(device.peripheral)
	}

	/// Send credentials for a visible network.
	func selectNetwork(_ network: NymeaWifiNetwork, password: String) {
		guard case .awaitingNetworkSelection = state else { return }
		transition(to: .sendingCredentials(ssid: network.essid))
		provisioningTask = Task {
			await doConnectToNetwork(ssid: network.essid, password: password, isHidden: false)
		}
	}

	/// Send credentials for a hidden (non-broadcasting) network.
	func selectHiddenNetwork(ssid: String, password: String) {
		guard case .awaitingNetworkSelection = state else { return }
		transition(to: .sendingCredentials(ssid: ssid))
		provisioningTask = Task {
			await doConnectToNetwork(ssid: ssid, password: password, isHidden: true)
		}
	}

	/// Abort the session and return to `.idle`.
	func cancel() {
		provisioningTask?.cancel()
		cleanupTask?.cancel()
		provisioningTask = nil
		cleanupTask = nil
		stopScanning()
		if let peripheral = targetPeripheral {
			central?.cancelPeripheralConnection(peripheral)
		}
		targetPeripheral = nil
		nymeaSession = nil
		central = nil
		centralDelegate = nil
		scanMode = .passive
		discoverable = []
		transition(to: .idle)
	}

	func reset() { cancel() }

	// MARK: - Scanning internals

	private func startScanning(mode: ScanMode) {
		scanMode = mode
		if central == nil {
			let delegate = NymeaCentralDelegate()
			delegate.manager = self
			centralDelegate = delegate
			// CBCentralManager dedicated to nymea provisioning — separate from the main
			// Meshtastic BLETransport instance so the two scans don't interfere.
			central = CBCentralManager(delegate: delegate, queue: .main)
		} else if central?.state == .poweredOn {
			// Already powered on; (re)issue the scan with the current mode's options.
			centralDidBecomeReady(central: central!)
		}
		startCleanupTask()
		// scanForPeripherals is called by the delegate once the manager reaches .poweredOn
	}

	private func stopScanning() {
		central?.stopScan()
		cleanupTask?.cancel()
		cleanupTask = nil
		discoveredDevices.removeAll()
		discoverable = []
		// Release the central if no provisioning session is using it. (During an
		// active session the central is needed for connect/disconnect; cancel()
		// will tear it down when the session ends.)
		if state == .idle && targetPeripheral == nil {
			central = nil
			centralDelegate = nil
		}
	}

	/// Called by `NymeaCentralDelegate` when the CBCentralManager reports `.poweredOn`.
	func centralDidBecomeReady(central: CBCentralManager) {
		// If we already have a target peripheral queued (beginProvisioning was called
		// before the central became ready), connect immediately and skip scanning.
		if case .connectingBLE = state, let target = targetPeripheral {
			central.connect(target)
			return
		}
		// Scan for all peripherals rather than filtering by service UUID here.
		//
		// The nymea-networkmanager README warns that if `ForceFullName` is set (or the
		// advertise name is longer than 8 characters), the Service UUID is displaced from
		// the advertisement packet — making service-UUID-filtered scans blind to the device.
		// We therefore scan broadly and apply our own filter in didDiscoverPeripheral, accepting
		// a peripheral if it either advertises a known nymea service UUID *or* its name
		// contains "mPWRD".
		//
		// Active scans request duplicates so RSSI updates live in the picker; passive
		// background scans omit duplicates to reduce battery impact while idle.
		let allowDuplicates = (scanMode == .active)
		central.scanForPeripherals(
			withServices: nil,
			options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
		)
		Logger.nymea.debug("🔧 Scanning for nymea devices (\(self.scanMode == .active ? "active" : "passive"), name/UUID filter applied in callback)…")
	}

	/// Called by the delegate each time a peripheral is (re-)discovered.
	func didDiscoverPeripheral(
		_ peripheral: CBPeripheral,
		advertisementData: [String: Any],
		rssi: Int
	) {
		// Accept the peripheral if it advertises a nymea service UUID or has a recognisable name.
		let advertisedUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
		let hasNymeaService = advertisedUUIDs.contains(nymeaWirelessServiceUUID)
			|| advertisedUUIDs.contains(nymeaNetworkServiceUUID)
		let hasNymeaName = peripheral.name.map {
			$0.localizedCaseInsensitiveContains("mPWRD") || $0.lowercased() == "nymea"
		} ?? false

		guard hasNymeaService || hasNymeaName else { return }

		let id = peripheral.identifier
		if var existing = discoveredDevices[id] {
			existing.rssi = rssi
			existing.lastSeen = Date()
			discoveredDevices[id] = existing
		} else {
			discoveredDevices[id] = NymeaDiscoveredDevice(
				id: id,
				name: peripheral.name ?? "mPWRD-OS",
				peripheral: peripheral,
				rssi: rssi,
				lastSeen: Date()
			)
			Logger.nymea.debug("🔧 Found nymea device: \(peripheral.name ?? "(no name)", privacy: .public) [\(peripheral.identifier)]")
		}
		publishDeviceList()
	}

	private func publishDeviceList() {
		let sorted = discoveredDevices.values.sorted { $0.rssi > $1.rssi }
		// Always publish to the passive list so the Connect view sees updates.
		discoverable = sorted
		// In an active provisioning session also drive the in-sheet picker state.
		switch state {
		case .scanningForDevices, .selectingDevice:
			transition(to: sorted.isEmpty ? .scanningForDevices : .selectingDevice(sorted))
		default:
			break
		}
	}

	/// Periodically removes peripherals not seen recently. Active scans use a tighter
	/// 20s window for responsive RSSI; passive scans use 30s to tolerate the lower
	/// duty cycle of `allowDuplicates: false`.
	private func startCleanupTask() {
		cleanupTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 s
				await self?.pruneStaleDevices()
			}
		}
	}

	@MainActor
	private func pruneStaleDevices() {
		let now = Date()
		let staleAfter: TimeInterval = (scanMode == .active) ? 20 : 30
		discoveredDevices = discoveredDevices.filter {
			now.timeIntervalSince($0.value.lastSeen) < staleAfter
		}
		publishDeviceList()
	}

	// MARK: - Connection callbacks (invoked by NymeaCentralDelegate → Task @MainActor)

	func centralDidConnectPeripheral(_ peripheral: CBPeripheral) {
		Logger.nymea.debug("🔧 BLE connected to \(peripheral.name ?? "unknown", privacy: .public)")
		let session = NymeaSession(peripheral: peripheral)
		nymeaSession = session
		provisioningTask = Task { await runProvisioningFlow(session: session) }
	}

	func centralDidFailToConnect(error: Error?) {
		let msg = error?.localizedDescription ?? "Failed to connect"
		Logger.nymea.error("🔧 BLE connection failed: \(msg, privacy: .public)")
		transition(to: .failed(msg))
	}

	func centralDidDisconnect(error: Error?) {
		provisioningTask?.cancel()
		guard case .success = state else {
			let msg = error?.localizedDescription ?? "Disconnected"
			Logger.nymea.error("🔧 Unexpected BLE disconnect: \(msg, privacy: .public)")
			transition(to: .failed("Device disconnected unexpectedly"))
			return
		}
		// Normal: device drops BLE after joining Wi-Fi.
	}

	// MARK: - Provisioning flow

	private func runProvisioningFlow(session: NymeaSession) async {
		do {
			try await session.connect()
			transition(to: .checkingNetworkState)
			try await session.enableNetworking()
			try await session.enableWireless()
			transition(to: .scanning)
			try await session.scan()
			try await Task.sleep(nanoseconds: 2_000_000_000) // let scan results settle
			let networks = try await session.getNetworks()
			// Filter out unnamed networks (we can't show "" usefully) and de-duplicate
			// by ESSID, keeping the strongest-signal entry for each name. Then sort
			// strongest-first for display.
			let filtered = networks.filter { !$0.essid.isEmpty }
			let deduped = Dictionary(grouping: filtered, by: { $0.essid })
				.compactMap { $0.value.max(by: { $0.signal < $1.signal }) }
				.sorted { $0.signal > $1.signal }
			transition(to: .awaitingNetworkSelection(deduped))
		} catch {
			Logger.nymea.error("🔧 Provisioning flow error: \(error.localizedDescription, privacy: .public)")
			transition(to: .failed(error.localizedDescription))
		}
	}

	private func doConnectToNetwork(ssid: String, password: String, isHidden: Bool) async {
		guard let session = nymeaSession else {
			transition(to: .failed("No active BLE session"))
			return
		}
		do {
			if isHidden {
				try await session.connectToHiddenNetwork(ssid: ssid, password: password)
			} else {
				try await session.connectToNetwork(ssid: ssid, password: password)
			}

			let stream = await session.wirelessStatusStream()
			guard try await waitForActivation(stream: stream) else {
				transition(to: .failed("Device could not connect to '\(ssid)'"))
				return
			}

			transition(to: .retrievingIPAddress)
			let info = try await session.getConnectionInfo()
			Logger.nymea.info("🔧 Provisioning success — IP: \(info.ipAddress, privacy: .public)")
			transition(to: .success(ipAddress: info.ipAddress))
		} catch {
			Logger.nymea.error("🔧 Credential error: \(error.localizedDescription, privacy: .public)")
			transition(to: .failed(error.localizedDescription))
		}
	}

	/// Returns `true` once `.activated` is seen, `false` on `.failed`, throws on timeout.
	private func waitForActivation(stream: AsyncStream<NymeaWirelessConnectionStatus>) async throws -> Bool {
		try await withThrowingTaskGroup(of: Bool.self) { group in
			group.addTask {
				for await status in stream {
					switch status {
					case .activated: return true
					case .failed:    return false
					default:         continue
					}
				}
				return false
			}
			group.addTask {
				try await Task.sleep(nanoseconds: 30_000_000_000)
				throw NymeaSessionError.timeout
			}
			let result = try await group.next()!
			group.cancelAll()
			return result
		}
	}

	// MARK: - Helpers

	private func transition(to newState: ProvisioningState) {
		Logger.nymea.debug("🔧 State → \(String(describing: newState))")
		state = newState
	}
}

// MARK: - CBCentralManager Delegate Bridge

final class NymeaCentralDelegate: NSObject, CBCentralManagerDelegate, @unchecked Sendable {

	weak var manager: NymeaProvisioningManager?

	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		guard central.state == .poweredOn else { return }
		Task { @MainActor [weak self] in
			self?.manager?.centralDidBecomeReady(central: central)
		}
	}

	func centralManager(
		_ central: CBCentralManager,
		didDiscover peripheral: CBPeripheral,
		advertisementData: [String: Any],
		rssi RSSI: NSNumber
	) {
		Task { @MainActor [weak self] in
			self?.manager?.didDiscoverPeripheral(peripheral, advertisementData: advertisementData, rssi: RSSI.intValue)
		}
	}

	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		Task { @MainActor [weak self] in
			self?.manager?.centralDidConnectPeripheral(peripheral)
		}
	}

	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		Task { @MainActor [weak self] in
			self?.manager?.centralDidFailToConnect(error: error)
		}
	}

	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		Task { @MainActor [weak self] in
			self?.manager?.centralDidDisconnect(error: error)
		}
	}
}
