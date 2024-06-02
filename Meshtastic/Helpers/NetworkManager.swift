//
//  NetworkManager.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen on 4/23/23.
//

import Foundation
import Network

class NetworkManager {
	static let shared = NetworkManager()
	// MARK: Public methods
	func runIfNetwork(completion: @escaping () -> Void ) {
		let pathMonitor = NWPathMonitor()
		pathMonitor.pathUpdateHandler = {
			guard $0.status == .satisfied else {
				// No network available
				logger.info("Network Not available")
				return pathMonitor.cancel()
			}
			pathMonitor.cancel()
			completion()
		}
		pathMonitor.start(queue: DispatchQueue.global(qos: .background))
	}
}
