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
import OSLog
import SwiftUI

private let discoveryLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "org.meshtastic.tv",
	category: "📡 Discovery"
)

struct DiscoveredNode: Identifiable, Hashable {
	let id: String        // node id (e.g. !fa6c5fac) when advertised, else service name
	let serviceName: String
	let name: String      // shortname / service name for display
	let host: String      // resolved hostname (e.g. Meshtastic.local)
	let port: Int
}

private struct BonjourServiceKey: Hashable {
	let domain: String
	let type: String
	let name: String

	init(_ service: NetService) {
		self.domain = service.domain
		self.type = service.type
		self.name = service.name
	}
}

protocol ServiceBrowsing: AnyObject {
	func setDelegate(_ delegate: NetServiceBrowserDelegate?)
	func searchForServices(ofType type: String, inDomain domainString: String)
	func stop()
}

extension NetServiceBrowser: ServiceBrowsing {
	func setDelegate(_ delegate: NetServiceBrowserDelegate?) {
		self.delegate = delegate
	}
}

@MainActor
final class NodeDiscovery: NSObject, ObservableObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {

	@Published private(set) var discovered: [DiscoveredNode] = []
	@Published private(set) var isBrowsing = false
	@Published private(set) var errorMessage: String?

	private let makeBrowser: @MainActor () -> any ServiceBrowsing
	private var browser: (any ServiceBrowsing)?
	private var resolving: [BonjourServiceKey: NetService] = [:]
	private var shouldRestartWhenActive = false

	init(makeBrowser: @escaping @MainActor () -> any ServiceBrowsing = { NetServiceBrowser() }) {
		self.makeBrowser = makeBrowser
		super.init()
	}

	func start() {
		guard !isBrowsing else {
			discoveryLogger.debug("📺 [Discovery] Bonjour browse already active")
			return
		}
		discovered = []
		errorMessage = nil
		let browser = makeBrowser()
		browser.setDelegate(self)
		self.browser = browser
		isBrowsing = true
		discoveryLogger.info("📺 [Discovery] Starting Bonjour browse")
		browser.searchForServices(ofType: "_meshtastic._tcp.", inDomain: "local.")
	}

	func stop() {
		discoveryLogger.info("📺 [Discovery] Stopping Bonjour browse")
		browser?.stop()
		browser?.setDelegate(nil)
		browser = nil
		for service in resolving.values {
			service.stop()
			service.delegate = nil
		}
		resolving.removeAll()
		isBrowsing = false
	}

	func retry() {
		stop()
		start()
	}

	func handle(scenePhase: ScenePhase) {
		switch scenePhase {
		case .background:
			// Only resume a browse that was active before suspension.
			shouldRestartWhenActive = isBrowsing
			stop()
		case .active:
			guard shouldRestartWhenActive else {
				discoveryLogger.debug("📺 [Discovery] Active without a pending Bonjour restart")
				return
			}
			shouldRestartWhenActive = false
			discoveryLogger.info("📺 [Discovery] Restarting Bonjour browse after resume")
			retry()
		case .inactive:
			break
		@unknown default:
			break
		}
	}

	// MARK: - NetServiceBrowserDelegate

	func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
		discoveryLogger.info("📺 [Discovery] Found Bonjour service \(service.name, privacy: .private(mask: .hash))")
		service.delegate = self
		let key = BonjourServiceKey(service)
		if let previous = resolving.updateValue(service, forKey: key), previous !== service {
			previous.stop()
			previous.delegate = nil
		}
		service.resolve(withTimeout: 5)
	}

	func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
		discoveryLogger.info("📺 [Discovery] Removed Bonjour service \(service.name, privacy: .private(mask: .hash))")
		if let pending = resolving.removeValue(forKey: BonjourServiceKey(service)) {
			pending.stop()
			pending.delegate = nil
			if pending !== service {
				service.stop()
				service.delegate = nil
			}
		} else {
			service.stop()
			service.delegate = nil
		}
		discovered.removeAll { $0.serviceName == service.name }
	}

	func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
		discoveryLogger.error("📺 [Discovery] Bonjour browse failed: \(String(describing: errorDict), privacy: .public)")
		self.browser?.setDelegate(nil)
		self.browser = nil
		isBrowsing = false
		errorMessage = String(localized: "Local network discovery failed. Check permission in Settings.")
	}

	// MARK: - NetServiceDelegate

	func netServiceDidResolveAddress(_ service: NetService) {
		let key = BonjourServiceKey(service)
		guard resolving[key] === service else {
			service.delegate = nil
			return
		}
		defer {
			resolving.removeValue(forKey: key)
			service.delegate = nil
		}
		guard let host = service.hostName, service.port > 0 else { return }
		discoveryLogger.info("📺 [Discovery] Resolved Bonjour service \(service.name, privacy: .private(mask: .hash))")

		let txt = service.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
		let shortname = txt["shortname"].flatMap { String(data: $0, encoding: .utf8) }
		let idString = txt["id"].flatMap { String(data: $0, encoding: .utf8) }

		let node = DiscoveredNode(
			id: idString ?? service.name,
			serviceName: service.name,
			name: shortname?.isEmpty == false ? shortname! : service.name,
			host: host.hasSuffix(".") ? String(host.dropLast()) : host,
			port: service.port
		)

		record(node)
	}

	/// Internal so the existing cross-target test seam can verify list reconciliation.
	func record(_ node: DiscoveredNode) {
		if let index = discovered.firstIndex(where: { $0.id == node.id }) {
			discovered[index] = node
		} else {
			discovered.append(node)
		}
	}

	func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
		discoveryLogger.error("📺 [Discovery] Failed to resolve \(service.name, privacy: .private(mask: .hash)): \(String(describing: errorDict), privacy: .public)")
		let key = BonjourServiceKey(service)
		if resolving[key] === service {
			resolving.removeValue(forKey: key)
		}
		service.delegate = nil
	}
}
