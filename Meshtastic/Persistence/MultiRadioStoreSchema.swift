// MultiRadioStoreSchema.swift
// Meshtastic
//
// SwiftData ownership boundary for persisted local-radio switching.

import SwiftData

enum MultiRadioStoreSchema {
	/// Mirrors Android's coarse database ownership: persisted radio data, discovery history,
	/// configuration snapshots, and rebuildable catalogs all follow the selected local radio.
	/// Keep this list explicit so every new production model requires an ownership decision.
	static let radioModels: [any PersistentModel.Type] = [
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
		TraceRouteNodePositionEntity.self,
		DeviceHardwareEntity.self,
		DeviceHardwareImageEntity.self,
		DeviceHardwareTagEntity.self,
		DeviceLinkEntity.self,
		FirmwareReleaseEntity.self,
		EventFirmwareEntity.self,
		AmbientLightingConfigEntity.self,
		AudioConfigEntity.self,
		BluetoothConfigEntity.self,
		CannedMessageConfigEntity.self,
		DetectionSensorConfigEntity.self,
		DeviceConfigEntity.self,
		DisplayConfigEntity.self,
		ExternalNotificationConfigEntity.self,
		LoRaConfigEntity.self,
		MeshBeaconConfigEntity.self,
		BroadcastTargetEntity.self,
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
		StatusMessageConfigEntity.self,
		StoreForwardConfigEntity.self,
		TAKConfigEntity.self,
		TrafficManagementConfigEntity.self,
		TelemetryConfigEntity.self,
		DiscoverySessionEntity.self,
		DiscoveryPresetResultEntity.self,
		DiscoveredNodeEntity.self,
		DiscoveredBeaconEntity.self
	]

	/// Phone-recorded routes have no Android radio-database counterpart. Registry models own
	/// identity and transport evidence independently of whichever radio store is active.
	static let globalModels: [any PersistentModel.Type] = RadioRegistrySchemaV1.models

	static var radioSchema: Schema {
		Schema(radioModels, version: MeshtasticSchemaV1.versionIdentifier)
	}

	static var globalSchema: Schema {
		Schema(versionedSchema: RadioRegistrySchemaV1.self)
	}

	static var combinedSchema: Schema {
		Schema(radioModels + globalModels)
	}
}
