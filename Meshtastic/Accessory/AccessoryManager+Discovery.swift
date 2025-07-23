//
//  AccessoryManager+Discovery.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/23/25.
//

import Foundation
import OSLog

extension AccessoryManager {

	private func discoverAllDevices() -> AsyncStream<Device> {
		AsyncStream { continuation in
			let tasks = transports.map { transport in
				Task {
					for await device in transport.discoverDevices() {
						continuation.yield(device)
					}
				}
			}
			continuation.onTermination = { _ in tasks.forEach { $0.cancel() } }
		}
	}

	func startDiscovery() {
		stopDiscovery()
		updateState(.discovering)

		discoveryTask = Task {
			for await newDevice in self.discoverAllDevices() {
				do {
					try Task.checkCancellation()

					// Update existing device or add new
					if let index = self.devices.firstIndex(where: { $0.id == newDevice.id }) {
						Logger.transport.debug("[Discovery] Device \(self.devices[index].name) already exists, updating its properties.")
						var existing = self.devices[index]
						existing.name = newDevice.name
						existing.transportType = newDevice.transportType
						existing.identifier = newDevice.identifier
						existing.connectionState = newDevice.connectionState
						existing.rssi = newDevice.rssi
						self.devices[index] = existing
					} else {
						Logger.transport.debug("[Discovery] \(newDevice.name) discovered with id \(newDevice.id), adding.")
						self.devices.append(newDevice)
					}

					// Update the list of discovered devices on the main thread for presentation
					// in the user interface
					self.devices = devices.sorted { $0.name < $1.name }

				} catch {
					break
				}
			}
		}

		rssiUpdateDuringDiscoveryTask = Task {
			for await rssiUpdate in self.rssiUpdatesDuringDiscovery() {
				updateDevice(deviceId: rssiUpdate.deviceId, key: \.rssi, value: rssiUpdate.rssi)
			}
		}
	}

	func stopDiscovery() {
		devices.removeAll()
		discoveryTask?.cancel()
		discoveryTask?.cancel()
		discoveryTask = nil
	}

	private func rssiUpdatesDuringDiscovery() -> AsyncStream<TransportRSSIUpdate> {
		AsyncStream { continuation in
			let tasks = transports.compactMap({ $0 as? WirelessTransport }).compactMap { transport in
				Task {
					for await rssiUpdate in await transport.rssiStream() {
						continuation.yield(rssiUpdate)
					}
				}
			}
			continuation.onTermination = { _ in tasks.forEach { $0.cancel() } }
		}
	}
}
