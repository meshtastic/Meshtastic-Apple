//
//  NavigateToButton.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 2/8/25.
//

import SwiftUI
import CoreLocation
import CoreData
import OSLog

struct NavigateToButton: View {
	var node: NodeInfoEntity

	var body: some View {
			Button {
				guard let userNum = node.user?.num else {
					Logger.services.error("NavigateToAction: Selected node does not exist")
					return
				}
				
				Logger.services.info("Fetching NodeInfoEntity for userNum: \(userNum)")
				
				let fetchRequest: NSFetchRequest<NodeInfoEntity> = NSFetchRequest(entityName: "NodeInfoEntity")
				fetchRequest.predicate = NSPredicate(format: "num == %lld", Int64(userNum))
				
				do {
					let fetchedNodes = try PersistenceController.shared.container.viewContext.fetch(fetchRequest)
					
					guard let nodeInfo = fetchedNodes.first else {
						Logger.services.error("NavigateToAction: Node with userNum \(userNum) not found in Core Data")
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
						Logger.services.warning("NavigateToAction: Node \(userNum) has invalid or missing coordinates")
					}
				} catch {
					Logger.services.error("NavigateToAction: Failed to fetch node with userNum \(userNum): \(error.localizedDescription)")
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
