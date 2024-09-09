//
//  NodePositionIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/10/24.
//

import Foundation
import AppIntents
import CoreLocation
import CoreData

struct NodePositionIntent: AppIntent {

	@Parameter(title: "Node Number")
	var nodeNum: Int

	static var title: LocalizedStringResource = "Get Node Position"
	static var description: IntentDescription = "Fetch the latest position of a cetain node"

	func perform() async throws -> some IntentResult & ReturnsValue<CLPlacemark> {
		if !BLEManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}
			let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "NodeInfoEntity")
			fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
			do {
				guard let fetchedNode = try PersistenceController.shared.container.viewContext.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity], fetchedNode.count == 1 else {
					throw $nodeNum.needsValueError("Could not find node")
				}

				let nodeInfo = fetchedNode[0]
				nodeInfo.latestEnvironmentMetrics?.batteryLevel
				if let latitude = nodeInfo.latestPosition?.coordinate.latitude,
				   let longitude = nodeInfo.latestPosition?.coordinate.longitude {
					let nodeLocation = CLLocation(latitude: latitude, longitude: longitude)

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
