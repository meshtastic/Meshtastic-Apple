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
	
	struct ResolvedService {
		let id: UUID
		let service: NetService
		let host: String
		let port: Int
	}

	override init() {
		super.init()
		browser = NetServiceBrowser()
		browser?.delegate = self
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


	
	func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
		self.service = service
		service.delegate = self
		service.resolve(withTimeout: 5)
	}

	func netServiceDidResolveAddress(_ service: NetService) {
		guard let host = service.hostName else {
			Logger.transport.error("🌐 [TCP] Failed to resolve host for service \(service.name, privacy: .public)")
			return
		}
		let port = service.port
		let ip = service.ipv4Address ?? "Unknown IP"

		// Use a mishmash of things and hash for stable? ID.
		let idString = "\(service.name):\(host):\(ip):\(port)".toUUIDFormatHash() ?? UUID()
		
		// Save the resolved service locally for later
		services[service.name] = ResolvedService(id: idString, service: service, host: host, port: port)
		
		let device = Device(id: idString,
							name: "\(service.name) (\(ip))",
							transportType: .tcp,
							identifier: "\(host):\(port)")
		continuation?.yield(.deviceFound(device))
	}

	func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
		Logger.transport.error("🌐 [TCP] Failed to resolve service \(sender.name, privacy: .public): \(errorDict, privacy: .public)")
	}

	func connect(to device: Device) async throws -> any Connection {
		Logger.transport.debug("🌐 [TCP] Connect to device: \(device.name, privacy: .public) with identifier: \(device.identifier, privacy: .public)")
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
		guard let leavingService = services[service.name] else {
			Logger.transport.error("🌐 [TCP] Service \(service.name, privacy: .public) not found in resolved services")
			return
		}

		// Notify the downstream
		self.continuation?.yield(.deviceLost(leavingService.id))
		
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

extension TCPTransport {
	static func requestLocalNetworkAuthorization() async -> Bool {
		await withCheckedContinuation { continuation in
			var resumeContinuation: CheckedContinuation<Bool, Never>? = continuation
			let resumeOnce: (Bool) -> Void = { result in
				resumeContinuation?.resume(returning: result)
				resumeContinuation = nil
			}

			let queue = DispatchQueue(label: "com.meshtastic.localNetworkAuth")

			let listener: NWListener
			do {
				listener = try NWListener(using: .tcp)
			} catch {
				Logger.transport.error("🌐 [TCP Permissions] Failed to create NWListener: \(error)")
				resumeOnce(false)
				return
			}

			// Use a unique name to avoid conflicts
			let uniqueName = UUID().uuidString
			listener.service = NWListener.Service(name: uniqueName, type: MESHTASTIC_SERVICE_TYPE, domain: MESHTASTIC_DOMAIN ?? "local.")

			listener.newConnectionHandler = { _ in }  // Required to avoid errors

			listener.stateUpdateHandler = { state in
				switch state {
				case .setup, .waiting, .ready, .cancelled:
					// No-op
					break
				case .failed(let error):
					Logger.transport.error("🌐 [TCP Permissions] Authorization NWListener failed: \(error)")
					resumeOnce(false)
					listener.cancel()
				@unknown default:
					Logger.transport.debug("🌐 [TCP Permissions] Authorization NWListener unknown state")
				}
			}

			listener.start(queue: queue)

			let parameters = NWParameters.tcp
			parameters.includePeerToPeer = true

			let browser = NWBrowser(for: .bonjour(type: MESHTASTIC_SERVICE_TYPE, domain: MESHTASTIC_DOMAIN ?? "local."), using: parameters)

			browser.stateUpdateHandler = { state in
				switch state {
				case .setup, .ready, .cancelled:
					// No-op
					break
				case .waiting(let error):
					Logger.transport.debug("🌐 [TCP Permissions] Authorization NWBrowser waiting: \(error)")
					if case .dns(let dnsError) = error, dnsError == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {  // Or check rawValue == -72003
						resumeOnce(false)
						browser.cancel()
						listener.cancel()
					}
				case .failed(let error):
					Logger.transport.error("🌐 [TCP Permissions] Authorization NWBrowser failed: \(error)")
					resumeOnce(false)
					browser.cancel()
					listener.cancel()
				@unknown default:
					Logger.transport.debug("🌐 [TCP] Authorization NWBrowser unknown state")
				}
			}

			// Key addition: Detect success when the browser finds the service (permission granted)
			browser.browseResultsChangedHandler = { results, _ in
				if !results.isEmpty {
					Logger.transport.debug("🌐 [TCP Permissions] Authorization NWBrowser found results, permission granted")
					resumeOnce(true)
					browser.cancel()
					listener.cancel()
				}
			}

			browser.start(queue: queue)
		}
	}
}
