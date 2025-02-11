//
//  NodeInfoEntity+CoreDataProperties.swift
//  
//
//  Created by Brian Floersch on 2/5/25.
//
//

import Foundation
import CoreData

extension NodeInfoEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<NodeInfoEntity> {
        return NSFetchRequest<NodeInfoEntity>(entityName: "NodeInfoEntity")
    }

    @NSManaged public var bleName: String?
    @NSManaged public var channel: Int32
    @NSManaged public var favorite: Bool
    @NSManaged public var firstHeard: Date?
    @NSManaged public var hopsAway: Int32
    @NSManaged public var id: Int64
    @NSManaged public var ignored: Bool
    @NSManaged public var lastHeard: Date?
    @NSManaged public var num: Int64
    @NSManaged public var peripheralId: String?
    @NSManaged public var rssi: Int32
    @NSManaged public var sessionExpiration: Date?
    @NSManaged public var sessionPasskey: Data?
    @NSManaged public var snr: Float
    @NSManaged public var viaMqtt: Bool
    @NSManaged public var ambientLightingConfig: AmbientLightingConfigEntity?
    @NSManaged public var bluetoothConfig: BluetoothConfigEntity?
    @NSManaged public var cannedMessageConfig: CannedMessageConfigEntity?
    @NSManaged public var detectionSensorConfig: DetectionSensorConfigEntity?
    @NSManaged public var deviceConfig: DeviceConfigEntity?
    @NSManaged public var displayConfig: DisplayConfigEntity?
    @NSManaged public var externalNotificationConfig: ExternalNotificationConfigEntity?
    @NSManaged public var loRaConfig: LoRaConfigEntity?
    @NSManaged public var metadata: DeviceMetadataEntity?
    @NSManaged public var mqttConfig: MQTTConfigEntity?
    @NSManaged public var myInfo: MyInfoEntity?
    @NSManaged public var networkConfig: NetworkConfigEntity?
    @NSManaged public var pax: NSOrderedSet?
    @NSManaged public var paxCounterConfig: PaxCounterConfigEntity?
    @NSManaged public var positionConfig: PositionConfigEntity?
    @NSManaged public var positions: NSOrderedSet?
    @NSManaged public var powerConfig: PowerConfigEntity?
    @NSManaged public var rangeTestConfig: RangeTestConfigEntity?
    @NSManaged public var rtttlConfig: RTTTLConfigEntity?
    @NSManaged public var securityConfig: SecurityConfigEntity?
    @NSManaged public var serialConfig: SerialConfigEntity?
    @NSManaged public var storeForwardConfig: StoreForwardConfigEntity?
    @NSManaged public var telemetries: NSOrderedSet?
    @NSManaged public var telemetryConfig: TelemetryConfigEntity?
    @NSManaged public var traceRoutes: NSOrderedSet?
    @NSManaged public var user: UserEntity?

}

// MARK: Generated accessors for pax
extension NodeInfoEntity {

    @objc(insertObject:inPaxAtIndex:)
    @NSManaged public func insertIntoPax(_ value: PaxCounterEntity, at idx: Int)

    @objc(removeObjectFromPaxAtIndex:)
    @NSManaged public func removeFromPax(at idx: Int)

    @objc(insertPax:atIndexes:)
    @NSManaged public func insertIntoPax(_ values: [PaxCounterEntity], at indexes: NSIndexSet)

    @objc(removePaxAtIndexes:)
    @NSManaged public func removeFromPax(at indexes: NSIndexSet)

    @objc(replaceObjectInPaxAtIndex:withObject:)
    @NSManaged public func replacePax(at idx: Int, with value: PaxCounterEntity)

    @objc(replacePaxAtIndexes:withPax:)
    @NSManaged public func replacePax(at indexes: NSIndexSet, with values: [PaxCounterEntity])

    @objc(addPaxObject:)
    @NSManaged public func addToPax(_ value: PaxCounterEntity)

    @objc(removePaxObject:)
    @NSManaged public func removeFromPax(_ value: PaxCounterEntity)

    @objc(addPax:)
    @NSManaged public func addToPax(_ values: NSOrderedSet)

    @objc(removePax:)
    @NSManaged public func removeFromPax(_ values: NSOrderedSet)

}

// MARK: Generated accessors for positions
extension NodeInfoEntity {

    @objc(insertObject:inPositionsAtIndex:)
    @NSManaged public func insertIntoPositions(_ value: PositionEntity, at idx: Int)

    @objc(removeObjectFromPositionsAtIndex:)
    @NSManaged public func removeFromPositions(at idx: Int)

    @objc(insertPositions:atIndexes:)
    @NSManaged public func insertIntoPositions(_ values: [PositionEntity], at indexes: NSIndexSet)

    @objc(removePositionsAtIndexes:)
    @NSManaged public func removeFromPositions(at indexes: NSIndexSet)

    @objc(replaceObjectInPositionsAtIndex:withObject:)
    @NSManaged public func replacePositions(at idx: Int, with value: PositionEntity)

    @objc(replacePositionsAtIndexes:withPositions:)
    @NSManaged public func replacePositions(at indexes: NSIndexSet, with values: [PositionEntity])

    @objc(addPositionsObject:)
    @NSManaged public func addToPositions(_ value: PositionEntity)

    @objc(removePositionsObject:)
    @NSManaged public func removeFromPositions(_ value: PositionEntity)

    @objc(addPositions:)
    @NSManaged public func addToPositions(_ values: NSOrderedSet)

    @objc(removePositions:)
    @NSManaged public func removeFromPositions(_ values: NSOrderedSet)

}

// MARK: Generated accessors for telemetries
extension NodeInfoEntity {

    @objc(insertObject:inTelemetriesAtIndex:)
    @NSManaged public func insertIntoTelemetries(_ value: TelemetryEntity, at idx: Int)

    @objc(removeObjectFromTelemetriesAtIndex:)
    @NSManaged public func removeFromTelemetries(at idx: Int)

    @objc(insertTelemetries:atIndexes:)
    @NSManaged public func insertIntoTelemetries(_ values: [TelemetryEntity], at indexes: NSIndexSet)

    @objc(removeTelemetriesAtIndexes:)
    @NSManaged public func removeFromTelemetries(at indexes: NSIndexSet)

    @objc(replaceObjectInTelemetriesAtIndex:withObject:)
    @NSManaged public func replaceTelemetries(at idx: Int, with value: TelemetryEntity)

    @objc(replaceTelemetriesAtIndexes:withTelemetries:)
    @NSManaged public func replaceTelemetries(at indexes: NSIndexSet, with values: [TelemetryEntity])

    @objc(addTelemetriesObject:)
    @NSManaged public func addToTelemetries(_ value: TelemetryEntity)

    @objc(removeTelemetriesObject:)
    @NSManaged public func removeFromTelemetries(_ value: TelemetryEntity)

    @objc(addTelemetries:)
    @NSManaged public func addToTelemetries(_ values: NSOrderedSet)

    @objc(removeTelemetries:)
    @NSManaged public func removeFromTelemetries(_ values: NSOrderedSet)

}

// MARK: Generated accessors for traceRoutes
extension NodeInfoEntity {

    @objc(insertObject:inTraceRoutesAtIndex:)
    @NSManaged public func insertIntoTraceRoutes(_ value: TraceRouteEntity, at idx: Int)

    @objc(removeObjectFromTraceRoutesAtIndex:)
    @NSManaged public func removeFromTraceRoutes(at idx: Int)

    @objc(insertTraceRoutes:atIndexes:)
    @NSManaged public func insertIntoTraceRoutes(_ values: [TraceRouteEntity], at indexes: NSIndexSet)

    @objc(removeTraceRoutesAtIndexes:)
    @NSManaged public func removeFromTraceRoutes(at indexes: NSIndexSet)

    @objc(replaceObjectInTraceRoutesAtIndex:withObject:)
    @NSManaged public func replaceTraceRoutes(at idx: Int, with value: TraceRouteEntity)

    @objc(replaceTraceRoutesAtIndexes:withTraceRoutes:)
    @NSManaged public func replaceTraceRoutes(at indexes: NSIndexSet, with values: [TraceRouteEntity])

    @objc(addTraceRoutesObject:)
    @NSManaged public func addToTraceRoutes(_ value: TraceRouteEntity)

    @objc(removeTraceRoutesObject:)
    @NSManaged public func removeFromTraceRoutes(_ value: TraceRouteEntity)

    @objc(addTraceRoutes:)
    @NSManaged public func addToTraceRoutes(_ values: NSOrderedSet)

    @objc(removeTraceRoutes:)
    @NSManaged public func removeFromTraceRoutes(_ values: NSOrderedSet)

}
