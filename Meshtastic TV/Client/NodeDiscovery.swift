//
//  NodeDiscovery.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Bonjour discovery of TCP-reachable Meshtastic nodes (`_meshtastic._tcp`), so a
//  node advertising on the local network appears in the connect list without the
//  user typing an IP — parity with the iOS/Android apps. Standalone NetServiceBrowser
//  (tvOS-capable); does not depend on the iOS AccessoryManager transport stack.
//
//  Requires NSLocalNetworkUsageDescription + NSBonjourServices (_meshtastic._tcp)
//  in Info.plist; tvOS shows a local-network permission prompt on first browse.
//

import Foundation

struct DiscoveredNode: Identifiable, Hashable {
	let id: String        // node id (e.g. !fa6c5fac) when advertised, else service name
	let name: String      // shortname / service name for display
	let host: String      // resolved hostname (e.g. Meshtastic.local)
	let port: Int
}

@MainActor
final class NodeDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {

	@Published private(set) var discovered: [DiscoveredNode] = []
	@Published private(set) var isBrowsing = false

	private let browser = NetServiceBrowser()
	private var resolving: Set<NetService> = []   // retain services while they resolve

	override init() {
		super.init()
		browser.delegate = self
	}

	func start() {
		guard !isBrowsing else { return }
		discovered = []
		isBrowsing = true
		browser.searchForServices(ofType: "_meshtastic._tcp.", inDomain: "local.")
	}

	func stop() {
		browser.stop()
		resolving.removeAll()
		isBrowsing = false
	}

	// MARK: - NetServiceBrowserDelegate

	func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
		service.delegate = self
		resolving.insert(service)
		service.resolve(withTimeout: 5)
	}

	func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
		discovered.removeAll { $0.id == Self.identity(for: service) || $0.name == service.name }
	}

	// MARK: - NetServiceDelegate

	func netServiceDidResolveAddress(_ service: NetService) {
		defer { resolving.remove(service) }
		guard let host = service.hostName, service.port > 0 else { return }

		let txt = service.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
		let shortname = txt["shortname"].flatMap { String(data: $0, encoding: .utf8) }
		let idString = txt["id"].flatMap { String(data: $0, encoding: .utf8) }

		let node = DiscoveredNode(
			id: idString ?? service.name,
			name: shortname?.isEmpty == false ? shortname! : service.name,
			host: host.hasSuffix(".") ? String(host.dropLast()) : host,
			port: service.port
		)

		if let index = discovered.firstIndex(where: { $0.id == node.id }) {
			discovered[index] = node
		} else {
			discovered.append(node)
		}
	}

	func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
		resolving.remove(service)
	}

	private static func identity(for service: NetService) -> String {
		service.name
	}
}
