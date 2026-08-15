//
//  TVNodeDiscoveryLifecycleTests.swift
//  MeshtasticTests
//

import Foundation
import SwiftUI
import Testing

private final class ServiceBrowserSpy: ServiceBrowsing {
	private(set) var searches: [(type: String, domain: String)] = []
	private(set) var stopCallCount = 0
	private weak var delegate: NetServiceBrowserDelegate?

	func setDelegate(_ delegate: NetServiceBrowserDelegate?) {
		self.delegate = delegate
	}

	func searchForServices(ofType type: String, inDomain domainString: String) {
		searches.append((type, domainString))
	}

	func stop() {
		stopCallCount += 1
	}
}

@MainActor
@Suite("tvOS node discovery lifecycle")
struct TVNodeDiscoveryLifecycleTests {
	@Test func backgroundResumeCreatesFreshBrowseAndDropsStaleNodes() {
		var browsers: [ServiceBrowserSpy] = []
		let discovery = NodeDiscovery {
			let browser = ServiceBrowserSpy()
			browsers.append(browser)
			return browser
		}
		discovery.start()
		discovery.record(
			DiscoveredNode(
				id: "!stale",
				serviceName: "stale-service",
				name: "Stale node",
				host: "stale.local",
				port: 4403
			)
		)

		discovery.handle(scenePhase: .background)
		discovery.handle(scenePhase: .active)

		#expect(browsers.count == 2)
		guard browsers.count == 2 else { return }
		#expect(browsers[0].stopCallCount == 1)
		#expect(browsers[1].searches.count == 1)
		#expect(browsers[1].searches[0].type == "_meshtastic._tcp.")
		#expect(browsers[1].searches[0].domain == "local.")
		#expect(discovery.isBrowsing)
		#expect(discovery.discovered.isEmpty)
	}

	@Test func activeAndInactiveWithoutBackgroundDoNotRestartColdLaunchBrowse() {
		var browsers: [ServiceBrowserSpy] = []
		let discovery = NodeDiscovery {
			let browser = ServiceBrowserSpy()
			browsers.append(browser)
			return browser
		}
		discovery.start()

		discovery.handle(scenePhase: .inactive)
		discovery.handle(scenePhase: .active)

		#expect(browsers.count == 1)
		guard browsers.count == 1 else { return }
		#expect(browsers[0].stopCallCount == 0)
		#expect(browsers[0].searches.count == 1)
		#expect(discovery.isBrowsing)
	}

	@Test func backgroundWhileNotBrowsingDoesNotStartHiddenBrowseOnResume() {
		var browsers: [ServiceBrowserSpy] = []
		let discovery = NodeDiscovery {
			let browser = ServiceBrowserSpy()
			browsers.append(browser)
			return browser
		}

		discovery.handle(scenePhase: .background)
		discovery.handle(scenePhase: .active)

		#expect(browsers.isEmpty)
		#expect(!discovery.isBrowsing)
	}

	@Test func repeatedBackgroundResumeCyclesCreateFreshBrowsers() {
		var browsers: [ServiceBrowserSpy] = []
		let discovery = NodeDiscovery {
			let browser = ServiceBrowserSpy()
			browsers.append(browser)
			return browser
		}
		discovery.start()

		for _ in 0..<2 {
			discovery.handle(scenePhase: .background)
			discovery.handle(scenePhase: .active)
		}

		#expect(browsers.count == 3)
		guard browsers.count == 3 else { return }
		#expect(browsers[0].stopCallCount == 1)
		#expect(browsers[1].stopCallCount == 1)
		#expect(browsers[2].searches.count == 1)
	}

	@Test func removalMatchesBonjourServiceName() {
		let discovery = NodeDiscovery { ServiceBrowserSpy() }
		discovery.record(
			DiscoveredNode(
				id: "!node-id",
				serviceName: "bonjour-service",
				name: "SHORT",
				host: "node.local",
				port: 4403
			)
		)
		let service = NetService(domain: "local.", type: "_meshtastic._tcp.", name: "bonjour-service")

		discovery.netServiceBrowser(NetServiceBrowser(), didRemove: service, moreComing: false)

		#expect(discovery.discovered.isEmpty)
	}

	@Test func failedBrowseStopsSpinnerAndOffersRetryState() {
		let discovery = NodeDiscovery { ServiceBrowserSpy() }
		discovery.start()

		discovery.netServiceBrowser(
			NetServiceBrowser(),
			didNotSearch: ["errorCode": NSNumber(value: -72000)]
		)

		#expect(!discovery.isBrowsing)
		#expect(discovery.errorMessage != nil)
	}
}
