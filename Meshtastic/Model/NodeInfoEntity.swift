//
//  NodeInfoEntity.swift
//  Meshtastic
//
//  SwiftData model for the central node information entity.
//

import Foundation
import SwiftData

@Model
final class NodeInfoEntity {
	var bleName: String?
	var channel: Int32 = 0
	var favorite: Bool = false
	var firstHeard: Date?
	var hopsAway: Int32 = 0
	var id: Int64 = 0
	var ignored: Bool = false
	var lastHeard: Date?
	var num: Int64 = 0
	var peripheralId: String?
	var rssi: Int32 = 0
	var sessionExpiration: Date?
	var sessionPasskey: Data?
	var snr: Float = 0.0
	var viaMqtt: Bool = false

	// Config relationships (to-one, cascade)
	@Relationship(deleteRule: .cascade, inverse: \AmbientLightingConfigEntity.ambientLightingConfigNode)
	var ambientLightingConfig: AmbientLightingConfigEntity?

	@Relationship(deleteRule: .cascade, inverse: \BluetoothConfigEntity.bluetoothConfigNode)
	var bluetoothConfig: BluetoothConfigEntity?

	@Relationship(deleteRule: .cascade, inverse: \CannedMessageConfigEntity.cannedMessagesConfigNode)
	var cannedMessageConfig: CannedMessageConfigEntity?

	@Relationship(deleteRule: .cascade, inverse: \DetectionSensorConfigEntity.detectionSensorConfigNode)
	var detectionSensorConfig: DetectionSensorConfigEntity?

	@Relationship(deleteRule: .cascade, inverse: \DeviceConfigEntity.deviceConfigNode)
	var deviceConfig: DeviceConfigEntity?

	@Relationship(deleteRule: .cascade, inverse: \DisplayConfigEntity.displayConfigNode)
	var displayConfig: DisplayConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \ExternalNotificationConfigEntity.externalNotificationConfigNode)
	var externalNotificationConfig: ExternalNotificationConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \LoRaConfigEntity.loRaConfigNode)
	var loRaConfig: LoRaConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \DeviceMetadataEntity.metadataNode)
	var metadata: DeviceMetadataEntity?

	@Relationship(deleteRule: .nullify, inverse: \MQTTConfigEntity.mqttConfigNode)
	var mqttConfig: MQTTConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \MyInfoEntity.myInfoNode)
	var myInfo: MyInfoEntity?

	@Relationship(deleteRule: .nullify, inverse: \NetworkConfigEntity.networkConfigNode)
	var networkConfig: NetworkConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \PaxCounterEntity.paxNode)
	var pax: [PaxCounterEntity] = []

	@Relationship(deleteRule: .nullify, inverse: \PaxCounterConfigEntity.paxCounterConfigNode)
	var paxCounterConfig: PaxCounterConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \PositionConfigEntity.positionConfigNode)
	var positionConfig: PositionConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \PositionEntity.nodePosition)
	var positions: [PositionEntity] = []

	@Relationship(deleteRule: .nullify, inverse: \PowerConfigEntity.powerConfigNode)
	var powerConfig: PowerConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \RangeTestConfigEntity.rangeTestConfigNode)
	var rangeTestConfig: RangeTestConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \RTTTLConfigEntity.rtttlConfigNode)
	var rtttlConfig: RTTTLConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \SecurityConfigEntity.securityConfigNode)
	var securityConfig: SecurityConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \SerialConfigEntity.serialConfigNode)
	var serialConfig: SerialConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \StoreForwardConfigEntity.storeForwardConfigNode)
	var storeForwardConfig: StoreForwardConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \TAKConfigEntity.takConfigNode)
	var takConfig: TAKConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \TelemetryEntity.nodeTelemetry)
	var telemetries: [TelemetryEntity] = []

	@Relationship(deleteRule: .nullify, inverse: \TelemetryConfigEntity.telemetryConfigNode)
	var telemetryConfig: TelemetryConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \TraceRouteEntity.node)
	var traceRoutes: [TraceRouteEntity] = []

	@Relationship(deleteRule: .nullify, inverse: \UserEntity.userNode)
	var user: UserEntity?

	init() {}
}
