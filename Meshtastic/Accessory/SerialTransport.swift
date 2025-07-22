//
//  SerialTransport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/22/25.
//

import Foundation
import OSLog

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

	private func getSerialPorts() -> [String] {
		do {
			let dev = "/dev"
			let contents = try FileManager.default.contentsOfDirectory(atPath: dev)
			return contents.filter { $0.hasPrefix("cu.") || $0.hasPrefix("tty.") }.map { dev + "/" + $0 }
		} catch {
			Logger.transport.error("[Serial] Error listing /dev: \(error)")
			return []
		}
	}

	func connect(to device: Device) async throws -> any Connection {
		return SerialConnection(path: device.identifier)
	}
}
