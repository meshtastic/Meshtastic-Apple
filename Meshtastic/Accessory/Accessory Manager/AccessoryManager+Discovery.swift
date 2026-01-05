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
					for await event in transport.discoverDevices() {
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
						
						if self.shouldAutomaticallyConnectToPreferredPeripheral,
						   UserDefaults.autoconnectOnDiscovery, UserDefaults.preferredPeripheralId == newDevice.id.uuidString {
							Logger.transport.debug("🔎 [Discovery] Found preferred peripheral \(newDevice.name)")
							self.connectToPreferredDevice()
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

	func stopDiscovery() {
		devices.removeAll()
		discoveryTask?.cancel()
		discoveryTask?.cancel()
		discoveryTask = nil
	}

}
