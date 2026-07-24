//
//  MapConnectivityMonitor.swift
//  Meshtastic
//
//  Tracks whether the device currently has ANY usable network path at all. Added as part of the fix
//  for the offline-map freeze investigated in DIAGNOSIS-offline-maps-freeze.md: MeshMapMK previously
//  had no connectivity awareness anywhere, so it kept asking MapKit for live-network extras (traffic,
//  POI) even with zero connectivity, adding to MapKit's own tile-fetch contention at exactly the
//  moment the offline vector basemap was doing its (now-chunked) rebuild work.
//
//  `NWPathMonitor` reports `.unsatisfied` only when there is genuinely no usable interface -- not
//  merely a slow/lossy one -- which is the specific "no cellular/data connectivity at all" condition
//  the bug report described, distinct from a live-but-weak connection.
//

import Foundation
import Network
import OSLog

/// Process-wide network reachability flag, cheap to observe from any SwiftUI view.
@MainActor
final class MapConnectivityMonitor: ObservableObject {
	static let shared = MapConnectivityMonitor()

	/// True when there is no usable network path (WiFi/cellular/wired/etc.) at all.
	@Published private(set) var isOffline = false

	private let monitor = NWPathMonitor()
	private let queue = DispatchQueue(label: "meshtastic.map.connectivity.monitor", qos: .utility)

	private init() {
		monitor.pathUpdateHandler = { [weak self] path in
			let unsatisfied = path.status == .unsatisfied
			Task { @MainActor [weak self] in
				guard let self, self.isOffline != unsatisfied else { return }
				self.isOffline = unsatisfied
				Logger.services.info("📶 [Map] connectivity changed: \(unsatisfied ? "offline" : "online", privacy: .public)")
			}
		}
		monitor.start(queue: queue)
	}

	deinit {
		monitor.cancel()
	}
}
