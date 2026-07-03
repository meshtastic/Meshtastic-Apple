//
//  Model+Sendable.swift
//  Meshtastic
//
//  SwiftData @Model classes are not Sendable by default, but their KeyPaths
//  are used inside #Predicate macros that may cross isolation boundaries.
//  Marking them @unchecked Sendable silences the spurious KeyPath<Model, T>
//  Sendable warnings in Swift 6 targeted concurrency mode.
//

import SwiftData

extension AmbientLightingConfigEntity: @unchecked Sendable {}
extension BluetoothConfigEntity: @unchecked Sendable {}
extension CannedMessageConfigEntity: @unchecked Sendable {}
extension ChannelEntity: @unchecked Sendable {}
extension DetectionSensorConfigEntity: @unchecked Sendable {}
extension DeviceConfigEntity: @unchecked Sendable {}
extension DeviceHardwareEntity: @unchecked Sendable {}
extension DeviceHardwareImageEntity: @unchecked Sendable {}
extension DeviceHardwareTagEntity: @unchecked Sendable {}
extension DeviceMetadataEntity: @unchecked Sendable {}
extension DiscoveredNodeEntity: @unchecked Sendable {}
extension DiscoveryPresetResultEntity: @unchecked Sendable {}
extension DiscoverySessionEntity: @unchecked Sendable {}
extension DisplayConfigEntity: @unchecked Sendable {}
extension ExternalNotificationConfigEntity: @unchecked Sendable {}
extension FirmwareReleaseEntity: @unchecked Sendable {}
extension LoRaConfigEntity: @unchecked Sendable {}
extension LocationEntity: @unchecked Sendable {}
extension MQTTConfigEntity: @unchecked Sendable {}
extension MessageEntity: @unchecked Sendable {}
extension MyInfoEntity: @unchecked Sendable {}
extension NetworkConfigEntity: @unchecked Sendable {}
extension NodeInfoEntity: @unchecked Sendable {}
extension PaxCounterConfigEntity: @unchecked Sendable {}
extension PaxCounterEntity: @unchecked Sendable {}
extension PositionConfigEntity: @unchecked Sendable {}
extension PositionEntity: @unchecked Sendable {}
extension PowerConfigEntity: @unchecked Sendable {}
extension RTTTLConfigEntity: @unchecked Sendable {}
extension RangeTestConfigEntity: @unchecked Sendable {}
extension RouteEntity: @unchecked Sendable {}
extension SecurityConfigEntity: @unchecked Sendable {}
extension SerialConfigEntity: @unchecked Sendable {}
extension StoreForwardConfigEntity: @unchecked Sendable {}
extension TAKConfigEntity: @unchecked Sendable {}
extension TelemetryConfigEntity: @unchecked Sendable {}
extension TelemetryEntity: @unchecked Sendable {}
extension TraceRouteEntity: @unchecked Sendable {}
extension TraceRouteHopEntity: @unchecked Sendable {}
extension UserEntity: @unchecked Sendable {}
extension WaypointEntity: @unchecked Sendable {}


