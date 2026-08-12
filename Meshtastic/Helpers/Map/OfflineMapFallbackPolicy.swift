//
//  OfflineMapFallbackPolicy.swift
//  Meshtastic
//
//  Determines when saved offline maps should render without changing the user's preference.
//

import Foundation
import Network

enum OfflineMapFallbackPolicy {
	static func shouldRenderOfflineMaps(
		userEnabled: Bool,
		hasSavedMaps: Bool,
		networkAvailable: Bool
	) -> Bool {
		userEnabled || (hasSavedMaps && !networkAvailable)
	}
}
@MainActor
final class OfflineMapConnectivityMonitor: ObservableObject {
	static let shared = OfflineMapConnectivityMonitor()

	@Published private(set) var isNetworkAvailable = true

	private let monitor = NWPathMonitor()
	private let queue = DispatchQueue(label: "org.meshtastic.offline-map-connectivity")

	private init() {
		monitor.pathUpdateHandler = { [weak self] path in
			Task { @MainActor in
				self?.isNetworkAvailable = path.status == .satisfied
			}
		}
		monitor.start(queue: queue)
	}

	deinit {
		monitor.cancel()
	}
}
