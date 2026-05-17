//
//  NodePositionIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/10/24.
//

import Foundation
import AppIntents
import CoreLocation
import SwiftData

struct NodePositionIntent: AppIntent {

	@Parameter(title: "Node Number")
	var nodeNum: Int

	static let title: LocalizedStringResource = "Get Node Position"
	static let description: IntentDescription = "Fetch the latest position of a cetain node"

	func perform() async throws -> some IntentResult & ReturnsValue<CLPlacemark> {
		if !(await AccessoryManager.shared.isConnected) {
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
			if let coord = nodeInfo.latestPosition?.nodeCoordinate {
				let nodeLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
				// Reverse geocode the CLLocation to get a CLPlacemark
				let geocoder = CLGeocoder()
				let placemarks = try await geocoder.reverseGeocodeLocation(nodeLocation)

				if let placemark = placemarks.first {
					return .result(value: placemark)
				} else {
					throw AppIntentErrors.AppIntentError.message("Error Reverse Geocoding Location")
				}
			} else {
				throw AppIntentErrors.AppIntentError.message("Node does not have positions")
			}
		} catch {
			throw AppIntentErrors.AppIntentError.message("Fetch Failure")
		}
	}
}
