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
		// A stopDiscovery() call is still awaiting transport teardown (discoveryTask is already
		// nil at this point, but the transports themselves haven't finished stopping yet) — don't
		// race a fresh scan against that in-flight shutdown. The caller that triggers this no-op
		// (e.g. appDidBecomeActive()) isn't the only path back to scanning: stopDiscovery()'s own
		// completion always leaves discovery either explicitly restarted by its caller or in a
		// state where the next relevant trigger (scenePhase change, connect flow, etc.) will call
		// startDiscovery() again (#2183 review).
		if isStoppingDiscovery {
			Logger.transport.debug("🔎 [Discovery] A stopDiscovery() call is still in flight; not starting a new scan.")
			return
		}
		if otaInProgress { return }
		updateState(.discovering)

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
						   !self.isSwitchingDevices,
						   UserDefaults.autoconnectOnDiscovery, UserDefaults.preferredPeripheralId == newDevice.id.uuidString {
							Logger.transport.debug("🔎 [Discovery] Found preferred peripheral \(newDevice.name)")
							self.connectToPreferredDevice(device: newDevice)
						}
						
						// Update the list of discovered devices on the main thread for presentation
						// in the user interface
						self.devices = devices.sorted { $0.name < $1.name }
						
					case .deviceLost(let deviceId):
						devices = devices.filter { $0.id != deviceId }
					
					case .deviceReportedRssi(let deviceId, let newRssi):
						updateDevice(deviceId: deviceId, key: \.rssi, value: newRssi)
					}
				} catch {
					break
				}
			}
		}
	}

	// Cancelling the outer discovery task only *requests* shutdown; it does not by itself wait
	// for CoreBluetooth (or TCP/Serial's equivalents) to actually stop. Cancellation propagates
	// async: the outer AsyncStream's cancellation tears down each per-transport Task, which
	// trips each transport's `discoverDevices()` `onTermination`. For BLE that spawns a *new*
	// unstructured Task to reach the actor and call `stopScanning()` (the thing that finally
	// calls `centralManager.stopScan()`) — a caller relying only on cancellation could resume
	// before that Task has run. Callers that need discovery verifiably off before a subsequent
	// step begins (e.g. AccessoryManager+Connect.swift's Step 0, ahead of BLE pairing — see
	// #2183 review) must await this function: it directly calls each transport's
	// `stopActiveDiscovery()` and awaits it, which for BLE executes `stopScanning()` inside the
	// actor with no further suspension, so the `await` only returns once scanning has actually
	// stopped.
	func stopDiscovery() async {
		isStoppingDiscovery = true
		defer { isStoppingDiscovery = false }
		devices.removeAll()
		discoveryTask?.cancel()
		discoveryTask = nil
		devices.removeAll()
		for transport in transports {
			await transport.stopActiveDiscovery()
		}
	}

}
