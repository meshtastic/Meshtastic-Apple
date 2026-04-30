//
//  MeshtasticSchemaV1.swift
//  Meshtastic
//
//  Initial SwiftData schema version capturing the baseline model state.
//

import Foundation
import SwiftData

enum MeshtasticSchemaV1: VersionedSchema {
	static var versionIdentifier = Schema.Version(1, 0, 0)

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
			BluetoothConfigEntity.self,
			CannedMessageConfigEntity.self,
			DetectionSensorConfigEntity.self,
			DeviceConfigEntity.self,
			DisplayConfigEntity.self,
			ExternalNotificationConfigEntity.self,
			LoRaConfigEntity.self,
			MQTTConfigEntity.self,
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
			TelemetryConfigEntity.self,
		]
	}
}
