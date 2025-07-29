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
					for await event in transport.discoverDevices() {
						continuation.yield(event)
					}
				}
			}
			continuation.onTermination = { _ in tasks.forEach { $0.cancel() } }
		}
	}

	func startDiscovery() {
		stopDiscovery()
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
							// This is a new device, add it to our list
							self.devices.append(newDevice)
						}
						
						if self.shouldAutomaticallyConnectToPreferredPeripheral, UserDefaults.preferredPeripheralId == newDevice.id.uuidString {
							Logger.transport.debug("[Discovery] Found preferred peripheral \(newDevice.name)")
							self.connectToPreferredDevice()
							self.shouldAutomaticallyConnectToPreferredPeripheral = false
						}
						
						// Update the list of discovered devices on the main thread for presentation
						// in the user interface
						self.devices = devices.sorted { $0.name < $1.name }
						
					case .deviceLost(let deviceId):
						devices.removeAll { $0.id == deviceId }
					
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
