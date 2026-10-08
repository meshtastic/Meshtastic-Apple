//
//  AccessoryManager+Discovery.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/23/25.
//

import Foundation
import OSLog

extension AccessoryManager {

	private func discoverAllDevices() -> AsyncStream<DiscoveryEvent> {
		AsyncStream { continuation in
			let tasks = transports.map { transport in
				Task {
					Logger.transport.info("🔎 [Discovery] Discovery stream started for transport \(String(describing: transport.type), privacy: .public)")
					for await event in await transport.discoverDevices() {
						continuation.yield(event)
					}
					Logger.transport.info("🔎 [Discovery] Discovery stream closed for transport \(String(describing: transport.type), privacy: .public)")
				}
			}
			continuation.onTermination = { _ in 
				Logger.transport.info("🔎 [Discovery] Cancelling discovery for all transports.")
				tasks.forEach { $0.cancel() }
			}
		}
	}

	func startDiscovery() {
		if discoveryTask != nil {
			Logger.transport.debug("🔎 [Discovery] Existing discovery task is active.")
			return
		}
		if otaInProgress { return }
		// Feature 021: discovery also runs while radios are connected, to add another one.
		// The connection state then stays as it is.
		if activeConnection == nil {
			updateState(.discovering)
			scheduleRememberedRadioFallback()
		}

		discoveryTask = Task { @MainActor in
			for await event in self.discoverAllDevices() {
				do {
					try Task.checkCancellation()
					switch event {
					case .deviceFound(let newDevice), .deviceUpdated(let newDevice):
						// Update existing device or add new
						if let index = self.devices.firstIndex(where: { $0.id == newDevice.id }) {
							// This device already exists.
							var existing = self.devices[index]
							existing.name = newDevice.name
							existing.transportType = newDevice.transportType
							existing.identifier = newDevice.identifier
							existing.connectionState = newDevice.connectionState
							existing.rssi = newDevice.rssi
							self.devices[index] = existing
						} else {
							// This is a new device, add it to our list if we are in the foreground
							if !(self.isInBackground) {
								self.devices.append(newDevice)
							} else {
								Logger.transport.debug("🔎 [Discovery] Found a new device but not in the foreground, not adding to our list: peripheral \(newDevice.name)")
							}
						}
						
						// Never auto-connect while a device switch is mid-flight: the switch's own
						// connect must be the only one running, or its database clear/restore
						// races a second node dump (nodes bleeding between radios).
						if self.shouldAutomaticallyConnectToPreferredPeripheralAfterError, !userRequestedConnectionCancellation,
						   !self.autoReconnectSuspendedForSession,
						   !self.isSwitchingDevices,
						   UserDefaults.autoconnectOnDiscovery, PreferredRadio.peripheralId == newDevice.id.uuidString {
							Logger.transport.debug("🔎 [Discovery] Found preferred peripheral \(newDevice.name)")
							self.connectToPreferredDevice(device: newDevice)
						}
						
						// Update the list of discovered devices on the main thread for presentation
						// in the user interface
						self.devices = devices.sorted { $0.name < $1.name }

						// Feature 021 (T156): a remembered radio that wasn't around when the first radio
						// connected comes back alongside the connected radios now, the first one
						// included or not (T317).
						self.recentlyDiscoveredDevices[newDevice.id] = newDevice
						if self.awaitedRememberedRadios.contains(newDevice.id), self.connectedRadioCount > 0 {
							self.awaitedRememberedRadios.remove(newDevice.id)
							if !self.isRadioConnected(newDevice.id) {
								Logger.transport.info("🔗🔁 [Additional] Remembered radio \(newDevice.name, privacy: .public) found; bringing it back")
								self.scheduleAdditionalRadioReconnect(newDevice)
							}
						}
						self.radioSeen(newDevice.id)
						
					case .deviceLost(let deviceId):
						devices = devices.filter { $0.id != deviceId }
						recentlyDiscoveredDevices.removeValue(forKey: deviceId)
						shownDiscoveryRssi.removeValue(forKey: deviceId)
					
					case .deviceReportedRssi(let deviceId, let newRssi):
						// Seen advertising: a radio waiting to come back connects now.
						radioSeen(deviceId)
						let now = ContinuousClock.now
						guard Self.showsDiscoveryRssi(newRssi, at: now, after: shownDiscoveryRssi[deviceId]) else { break }
						shownDiscoveryRssi[deviceId] = ShownRssi(rssi: newRssi, at: now)
						updateDevice(deviceId: deviceId, key: \.rssi, value: newRssi)
					}
				} catch {
					break
				}
			}
		}
	}

	/// An RSSI discovery showed for a radio, and when.
	struct ShownRssi: Equatable, Sendable {
		let rssi: Int
		let at: ContinuousClock.Instant
	}

	/// How far a radio's RSSI must move, or how long must pass, before discovery shows a new
	/// value (review V39). Scanning reports every advertisement, several a second per radio, and
	/// each write to `devices` redraws every view that observes the manager, in every window.
	/// A move shows after `discoveryRssiMinInterval` at the soonest: a weak, distant radio's RSSI
	/// often swings by the step between advertisements (review V40-3).
	nonisolated static let discoveryRssiStep = 5
	nonisolated static let discoveryRssiMinInterval: Duration = .seconds(2)
	nonisolated static let discoveryRssiInterval: Duration = .seconds(5)

	/// Whether a sighting's RSSI is worth showing, `last` being the one shown before.
	nonisolated static func showsDiscoveryRssi(_ rssi: Int, at now: ContinuousClock.Instant, after last: ShownRssi?) -> Bool {
		guard let last else { return true }
		let elapsed = now - last.at
		return elapsed >= discoveryRssiInterval
			|| (elapsed >= discoveryRssiMinInterval && abs(rssi - last.rssi) >= discoveryRssiStep)
	}

	/// Stops discovery once nothing needs it (reviews V39, V40-2): no Connect screen shows, a radio
	/// is connected, and no radio waits for discovery to bring it back: the first radio
	/// (`awaitsFirstRadio`), a radio alongside that dropped (review V45-2), or a remembered radio
	/// (T156). With no radio connected it goes on, as on `main`.
	func stopDiscoveryWhenUnneeded() {
		guard connectScreens.isEmpty, connectedRadioCount > 0, !awaitsFirstRadio, additionalRadioReconnects.isEmpty,
			  awaitedRememberedRadios.isEmpty else { return }
		stopDiscovery()
	}

	/// The first radio is away and discovery would connect it when it sees it (the auto-connect of
	/// the preferred radio above, `connectToPreferredDevice`): after a drop, not after the user's
	/// Disconnect, and not when the preferred radio is connected alongside, as it is after
	/// Disconnect on the first radio (review V42-1). A connect of it that's failing still counts as
	/// away: its teardown checks this while the attempt is registered (review V43-1).
	var awaitsFirstRadio: Bool {
		guard !isConnected, let preferredId = UUID(uuidString: PreferredRadio.peripheralId) else { return false }
		return additionalRadios[preferredId] == nil && UserDefaults.autoconnectOnDiscovery
			&& shouldAutomaticallyConnectToPreferredPeripheralAfterError && !userRequestedConnectionCancellation
			&& !autoReconnectSuspendedForSession
	}

	/// A Connect screen shows: discovery goes on while it does.
	func connectScreenAppeared(_ id: UUID) {
		connectScreens.insert(id)
	}

	/// A Connect screen has gone: discovery stops if nothing else needs it.
	func connectScreenDisappeared(_ id: UUID) {
		connectScreens.remove(id)
		stopDiscoveryWhenUnneeded()
	}

	func stopDiscovery() {
		devices.removeAll()
		discoveryTask?.cancel()
		discoveryTask = nil
		devices.removeAll()
	}

}
