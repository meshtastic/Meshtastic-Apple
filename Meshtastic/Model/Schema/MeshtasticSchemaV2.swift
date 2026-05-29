//
//  MeshtasticSchemaV2.swift
//  Meshtastic
//
//  Adds LocalStats noise floor telemetry.
//

import Foundation
import SwiftData

enum MeshtasticSchemaV2: VersionedSchema {
	static var versionIdentifier = Schema.Version(2, 0, 0)

	static var models: [any PersistentModel.Type] {
		[
			// Core entities
			NodeInfoEntity.self,
			UserEntity.self,
			MyInfoEntity.self,
			MessageEntity.self,
			ChannelEntity.self,
			PositionEntity.self,
			WaypointEntity.self,
			DeviceMetadataEntity.self,
			TelemetryEntity.self,
			PaxCounterEntity.self,
			TraceRouteEntity.self,
			TraceRouteHopEntity.self,
			RouteEntity.self,
			LocationEntity.self,
			// Device hardware & firmware entities
			DeviceHardwareEntity.self,
			DeviceHardwareImageEntity.self,
			DeviceHardwareTagEntity.self,
			FirmwareReleaseEntity.self,
			// Config entities
			AmbientLightingConfigEntity.self,
			AudioConfigEntity.self,
			BluetoothConfigEntity.self,
			CannedMessageConfigEntity.self,
			DetectionSensorConfigEntity.self,
			DeviceConfigEntity.self,
			DisplayConfigEntity.self,
			ExternalNotificationConfigEntity.self,
			LoRaConfigEntity.self,
			MQTTConfigEntity.self,
			NeighborInfoConfigEntity.self,
			NetworkConfigEntity.self,
			PaxCounterConfigEntity.self,
			PositionConfigEntity.self,
			PowerConfigEntity.self,
			RangeTestConfigEntity.self,
			RTTTLConfigEntity.self,
			SecurityConfigEntity.self,
			SerialConfigEntity.self,
			StoreForwardConfigEntity.self,
			TAKConfigEntity.self,
			TrafficManagementConfigEntity.self,
			TelemetryConfigEntity.self,
			// Discovery entities
			DiscoverySessionEntity.self,
			DiscoveryPresetResultEntity.self,
			DiscoveredNodeEntity.self
		]
	}
}
