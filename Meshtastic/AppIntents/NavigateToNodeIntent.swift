//
//  NavigateToNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 2/8/25.
//

import Foundation
import AppIntents
import CoreLocation
import SwiftData
import UIKit

@available(iOS 16.4, *)
struct NavigateToNodeIntent: ForegroundContinuableIntent {

	static var title: LocalizedStringResource = "Navigate to Node Position"
	static var openAppWhenRun: Bool = false

	@Parameter(title: "Node Number")
	var nodeNum: Int

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		if !BLEManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		let nodeNumInt64 = Int64(nodeNum)
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.num == nodeNumInt64 }
		)
		descriptor.fetchLimit = 1

		do {
			let fetchedNode = try await MainActor.run { try PersistenceController.shared.context.fetch(descriptor) }
			guard fetchedNode.count == 1 else {
				throw $nodeNum.needsValueError("Could not find node")
			}

			let nodeInfo = fetchedNode[0]
			if let latitude = nodeInfo.latestPosition?.coordinate.latitude,
			   let longitude = nodeInfo.latestPosition?.coordinate.longitude {

				let url = URL(string: "maps://?saddr=&daddr=\(latitude),\(longitude)")

				if let mapURL = url, UIApplication.shared.canOpenURL(mapURL) {
					// Request to continue in foreground before opening the app
					try await requestToContinueInForeground()

					// Open Apple Maps for navigation
					UIApplication.shared.open(mapURL, options: [:], completionHandler: nil)
					return .result(dialog: "Navigating to node location.")
				} else {
					throw AppIntentErrors.AppIntentError.message("Unable to open Apple Maps.")
				}
			} else {
				throw AppIntentErrors.AppIntentError.message("Node does not have a recorded position.")
			}
		} catch {
			throw AppIntentErrors.AppIntentError.message("Failed to fetch node data.")
		}
	}
}
