//
//  SerialTransport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/22/25.
//

import Foundation
import OSLog
import IOKit.serial

class SerialTransport: Transport {

	let type: TransportType = .serial
	var status: TransportStatus = .uninitialized

	func discoverDevices() -> AsyncStream<Device> {
		AsyncStream { cont in
			self.status = .discovering
			Task {
				while true {
					let ports = self.getSerialPorts()
					for port in ports {
						let id = port.toUUIDFormatHash() ?? UUID()
						cont.yield(Device(id: id,
										  name: port.components(separatedBy: "/").last ?? port,
										  transportType: .serial,
										  identifier: port))
					}
					try? await Task.sleep(for: .seconds(5))
				}
			}
			cont.onTermination = { _ in
				self.status = .ready
			}
		}
	}

//  DEPRICATED: old approach is just matching filenames
//	private func getSerialPorts() -> [String] {
//		do {
//			let dev = "/dev"
//			let contents = try FileManager.default.contentsOfDirectory(atPath: dev)
//			return contents.filter { $0.hasPrefix("cu.") || $0.hasPrefix("tty.") }.map { dev + "/" + $0 }
//		} catch {
//			Logger.transport.error("[Serial] Error listing /dev: \(error)")
//			return []
//		}
//	}

	// New approach, return only specific USB serial devices
	private func getSerialPorts() -> [String] {
		var serialPortIterator: io_iterator_t = 0
		var paths: [String] = []

		// Create a matching dictionary for all serial BSD services
		guard let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) as? [String: Any] else {
			return []
		}
		_ = matchingDict.merging([kIOSerialBSDTypeKey: kIOSerialBSDAllTypes]) { _, new in new }

		// Get the iterator for matching services
		let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict as CFDictionary, &serialPortIterator)
		if result != KERN_SUCCESS {
			return []
		}
		defer { IOObjectRelease(serialPortIterator) }

		// Iterate through services and extract callout paths (/dev/cu.xxx) only if they have a USB Serial Number property
		var serialService: io_object_t = 0
		let usbSerialKey = "USB Serial Number" as CFString
		let searchOptions: IOOptionBits = UInt32(kIORegistryIterateRecursively | kIORegistryIterateParents)

		repeat {
			serialService = IOIteratorNext(serialPortIterator)
			if serialService != 0 {
				// Check for USB Serial Number in the service or its parents
				if IORegistryEntrySearchCFProperty(serialService, kIOServicePlane, usbSerialKey, kCFAllocatorDefault, searchOptions) != nil {
					// Property exists, so this is a USB serial device; get the path
					if let path = IORegistryEntryCreateCFProperty(serialService, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? String {
						paths.append(path)
					}
				}
				IOObjectRelease(serialService)
			}
		} while serialService != 0

		return paths.sorted()  // Sort for consistent UX
	}

	func connect(to device: Device) async throws -> any Connection {
		return SerialConnection(path: device.identifier)
	}
}
