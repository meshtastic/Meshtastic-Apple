//
//  MeshtasticSchema.swift
//  Meshtastic
//
//  SwiftData schema definition and migration plan for migrating from Core Data.
//

import Foundation
import SwiftData

/// All model types in the Meshtastic schema
enum MeshtasticSchema {
	static var allModels: [any PersistentModel.Type] {
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
