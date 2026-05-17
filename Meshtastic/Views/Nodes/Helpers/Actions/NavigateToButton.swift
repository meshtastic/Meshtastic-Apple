//
//  NavigateToButton.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 2/8/25.
//

import SwiftUI
import CoreLocation
import SwiftData
import OSLog

struct NavigateToButton: View {
	var node: NodeInfoEntity

	var body: some View {
		Button {
			guard let userNum = node.user?.num else {
				Logger.services.error("NavigateToAction: Selected node does not exist")
				return
			}
			Logger.services.info("Fetching NodeInfoEntity for userNum: \(userNum, privacy: .public)")

			var descriptor = FetchDescriptor<NodeInfoEntity>(
				predicate: #Predicate<NodeInfoEntity> { $0.num == userNum }
			)
			descriptor.fetchLimit = 1

			do {
				let fetchedNodes = try PersistenceController.shared.context.fetch(descriptor)
				guard let nodeInfo = fetchedNodes.first else {
					Logger.services.error("NavigateToAction: Node with userNum \(userNum, privacy: .public) not found in Core Data")
					return
				}

				if let latitude = nodeInfo.latestPosition?.latitude,
				   let longitude = nodeInfo.latestPosition?.longitude {
					if let url = URL(string: "maps://?saddr=&daddr=\(latitude),\(longitude)") {
						UIApplication.shared.open(url, options: [:], completionHandler: nil)
					} else {
						Logger.services.error("Failed to create URL for navigation")
					}
				} else {
					Logger.services.warning("NavigateToAction: Node \(userNum, privacy: .public) has invalid or missing coordinates")
				}
			} catch {
				Logger.services.error("NavigateToAction: Failed to fetch node with userNum \(userNum, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		} label: {
			Label {
				Text("Navigate to node")
			} icon: {
				Image(systemName: "map")
					.symbolRenderingMode(.hierarchical)
			}
		}
	}
}

// TODO: Fix preview for SwiftData
/*
#Preview {
	let node = NodeInfoEntity()
	node.num = 123456789
	let user = UserEntity()
	user.longName = "Test Node"
	user.shortName = "TN"
	user.num = 123456789
	node.user = user
	NavigateToButton(node: node)
}
*/
