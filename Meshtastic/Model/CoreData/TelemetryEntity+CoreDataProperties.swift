//
//  TelemetryEntity+CoreDataProperties.swift
//
//
//  Created by Jake Bordens on 12/26/24.
//
//

import Foundation
import CoreData

// Manual implementation of the TelemetryEntry object for CoreData.
//   Add non-optional scalar types here using the standard @NSManaged proprty wrapper
//   Add optional/non-optional object types here using the standard @NSManaged proprty wrapper
//   CoreData is based on Objective-C which natively supports optionals for class types and
//   non-optional scalars.

extension TelemetryEntity {

	@nonobjc public class func fetchRequest() -> NSFetchRequest<TelemetryEntity> {
		return NSFetchRequest<TelemetryEntity>(entityName: "TelemetryEntity")
	}

	@NSManaged public var time: Date?
	@NSManaged public var metricsType: Int32
	@NSManaged public var numOnlineNodes: Int32
	@NSManaged public var numPacketsRx: Int32
	@NSManaged public var numPacketsRxBad: Int32
	@NSManaged public var numPacketsTx: Int32
	@NSManaged public var numRxDupe: Int32
	@NSManaged public var numTotalNodes: Int32
	@NSManaged public var numTxRelay: Int32
	@NSManaged public var numTxRelayCanceled: Int32
	@NSManaged public var nodeTelemetry: NodeInfoEntity?

}
