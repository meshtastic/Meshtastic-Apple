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

let MESHTASTIC_SERVICE_TYPE = "_meshtastic._tcp."
let MESHTASTIC_DOMAIN = "local."

class TCPTransport: NSObject, Transport, NetServiceBrowserDelegate, NetServiceDelegate {
	let type: TransportType = .tcp
	var status: TransportStatus = .uninitialized

	private var browser: NetServiceBrowser?
	private var services: [String: ResolvedService] = [:] // Key: service.name
	private var continuation: AsyncStream<Device>.Continuation?

	private var service: NetService?

	struct ResolvedService {
		let service: NetService
		let host: String
		let port: Int
	}

	override init() {
		super.init()
		browser = NetServiceBrowser()
		browser?.delegate = self
	}

	func discoverDevices() -> AsyncStream<Device> {
		AsyncStream { cont in
			self.continuation = cont
			self.status = .discovering
			Task {
				_ = await self.requestLocalNetworkAuthorization()
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
		continuation?.yield(device)
	}

	func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
		Logger.transport.error("[TCP] Failed to resolve service \(sender.name): \(errorDict)")
	}

	func connect(to device: Device) async throws -> any Connection {
		Logger.transport.error("[TCP] Connect to device: \(device.name) with identifier: \(device.identifier)")
		let parts = device.identifier.split(separator: ":")
		guard parts.count == 2, let port = Int(parts[1]) else {
			throw AccessoryError.connectionFailed("Invalid identifier format")
		}
		let host = String(parts[0])
		return try await TCPConnection(host: host, port: port)
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
