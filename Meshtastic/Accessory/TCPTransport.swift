//
//  TCPTransport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/19/25.
//

import Foundation
import Network
import OSLog
import MeshtasticProtobufs
import SwiftUI

let MESHTASTIC_SERVICE_TYPE = "_meshtastic._tcp."
let MESHTASTIC_DOMAIN = "local."

class TCPTransport: NSObject, Transport, NetServiceBrowserDelegate, NetServiceDelegate {
	
	let type: TransportType = .tcp
	var status: TransportStatus = .uninitialized
	// TODO: Move to NWBrowser (NetServiceBrowser is depricated)
	private var browser: NetServiceBrowser?
	private var services: [String: ResolvedService] = [:] // Key: service.name
	private var continuation: AsyncStream<DiscoveryEvent>.Continuation?

	private var service: NetService?

	// Transport Properties
	let requiresPeriodicHeartbeat = true
	let supportsManualConnection = true
	
	let icon = Image(systemName: "network")
	let name = "TCP"

	struct ResolvedService {
		let service: NetService
		let host: String
		let port: Int
	}

	override init() {
		super.init()
		browser = NetServiceBrowser()
		browser?.delegate = self
		Task {
			_ = await self.requestLocalNetworkAuthorization()
		}
	}

	func discoverDevices() -> AsyncStream<DiscoveryEvent> {
		AsyncStream { cont in
			self.continuation = cont
			self.status = .discovering
			Task {
				self.browser?.searchForServices(ofType: MESHTASTIC_SERVICE_TYPE, inDomain: MESHTASTIC_DOMAIN)
			}
			cont.onTermination = { _ in
				self.browser?.stop()
				self.services.removeAll()
				self.continuation = nil
				self.status = .ready
			}
		}
	}

	private var resumeContinuation: CheckedContinuation<Bool, Never>?
	private var resumed = false
	private func resumeOnce(with value: Bool) {
		if !resumed {
			resumed = true
			resumeContinuation?.resume(returning: value)
		}
	}

	private func requestLocalNetworkAuthorization() async -> Bool {
		await withCheckedContinuation { continuation in
			resumeContinuation = continuation
			guard let port = NWEndpoint.Port(rawValue: 0) else {
				resumeOnce(with: false)
				return
			}
			guard let listener = try? NWListener(using: .tcp, on: port) else {
				resumeOnce(with: false)
				return
			}
			listener.service = NWListener.Service(name: "preflight", type: "_preflight._tcp", domain: "local")
			listener.newConnectionHandler = { _ in }
			listener.stateUpdateHandler = { state in
				if case .failed = state {
					self.resumeOnce(with: false)
					listener.cancel()
				}
			}
			listener.start(queue: .main)

			let parameters = NWParameters.tcp
			parameters.includePeerToPeer = true
			let browser = NWBrowser(for: .bonjour(type: "_preflight._tcp", domain: "local"), using: parameters)
			browser.stateUpdateHandler = { state in
				switch state {
				case .ready:
					self.resumeOnce(with: true)
					browser.cancel()
					listener.cancel()
				case .failed:
					self.resumeOnce(with: false)
					browser.cancel()
					listener.cancel()
				default:
					break
				}
			}
			browser.start(queue: .main)
		}
	}

	func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
		self.service = service
		service.delegate = self
		service.resolve(withTimeout: 5)
	}

	func netServiceDidResolveAddress(_ service: NetService) {
		guard let host = service.hostName else {
			Logger.transport.error("[TCP] Failed to resolve host for service \(service.name)")
			return
		}
		let port = service.port
		services[service.name] = ResolvedService(service: service, host: host, port: port)
		let ip = service.ipv4Address ?? "Unknown IP"

		// Use a mishmash of things and hash for stable? ID.
		let idString = "\(service.name):\(host):\(ip):\(port)".toUUIDFormatHash() ?? UUID()
		let device = Device(id: idString,
							name: "\(service.name) (\(ip))",
							transportType: .tcp,
							identifier: "\(host):\(port)")
		continuation?.yield(.deviceFound(device))
	}

	func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
		Logger.transport.error("[TCP] Failed to resolve service \(sender.name): \(errorDict)")
	}

	func connect(to device: Device) async throws -> any Connection {
		Logger.transport.error("[TCP] Connect to device: \(device.name) with identifier: \(device.identifier)")
		let parts = device.identifier.split(separator: ":")
		
		var host: String?
		var port: Int?
		
		switch parts.count {
		case 1:
			// host & default port
			host = String(parts[0])
			port = 4403
		case 2:
			// host & port
			host = String(parts[0])
			port = Int(parts[1])
		default:
			throw AccessoryError.connectionFailed("Invalid identifier format")
		}
		guard let host, let port else {
			throw AccessoryError.connectionFailed("Invalid identifier format")
		}
		
		return try await TCPConnection(host: host, port: port)
	}
	
	func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
		guard let host = service.hostName else {
			Logger.transport.error("[TCP] Failed to resolve host for service \(service.name)")
			return
		}
		let port = service.port
		let ip = service.ipv4Address ?? "Unknown IP"
		// Use a mishmash of things and hash for stable? ID.
		
		guard let idString = "\(service.name):\(host):\(ip):\(port)".toUUIDFormatHash() else {
			Logger.transport.error("[TCP] Unable to synthesize an UUID for service \(service.name)")
			return
		}

		// Notify the downstream
		self.continuation?.yield(.deviceLost(idString))
		
		// Clean up the resolved services list
		var keysToRemove = [String]()
		for (key, value) in services where value.service == service {
			keysToRemove.append(key)
		}
		for removeKey in keysToRemove {
			services.removeValue(forKey: removeKey)
		}
	}
	
	func manuallyConnect(withConnectionString: String) async throws {
		let hashedIdentifier = withConnectionString.toUUIDFormatHash() ?? UUID()
		let manualDevice = Device(id: hashedIdentifier,
								  name: "\(withConnectionString) (Manual)",
								  transportType: .tcp, identifier: withConnectionString)
		try await AccessoryManager.shared.connect(to: manualDevice)
	}

}

extension NetService {
	var ipv4Address: String? {
		for addressData in addresses ?? [] {
			// sockaddr_in is typically 16 bytes; skip if too small
			guard addressData.count >= 16 else { continue }

			// Byte 1: sin_family (AF_INET == 2 for IPv4)
			let family = addressData[1]
			guard family == UInt8(AF_INET) else { continue }

			// Bytes 4-7: sin_addr.s_addr (IPv4 address in network byte order)
			let ipBytes = addressData[4..<8]

			// Convert each byte to string and join with dots
			return ipBytes.map { String($0) }.joined(separator: ".")
		}
		return nil
	}
}
