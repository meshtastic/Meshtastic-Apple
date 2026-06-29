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
	/// Live status message broadcast by the node over NODE_STATUS_APP (nil when empty).
	/// Distinct from `statusMessageConfig`, which is the configured value retrieved via admin.
	var nodeStatus: String?
	@Attribute(.unique) var num: Int64 = 0
	var peripheralId: String?
	var rssi: Int32 = 0
	var sessionExpiration: Date?
	var sessionPasskey: Data?
	var snr: Float = 0.0
	var viaMqtt: Bool = false

	// Config relationships (to-one, cascade)
	@Relationship(deleteRule: .cascade, inverse: \AmbientLightingConfigEntity.ambientLightingConfigNode)
	var ambientLightingConfig: AmbientLightingConfigEntity?

	@Relationship(deleteRule: .cascade, inverse: \AudioConfigEntity.audioConfigNode)
	var audioConfig: AudioConfigEntity?

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

	@Relationship(deleteRule: .nullify, inverse: \NeighborInfoConfigEntity.neighborInfoConfigNode)
	var neighborInfoConfig: NeighborInfoConfigEntity?

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

	/// O(1) cache of this node's current "latest" position, maintained on insert so the hot
	/// position-ingest path never has to scan the (large, unindexed) PositionEntity table to
	/// find/clear the previous latest. Read via the `latestPosition` accessor, which falls back
	/// to a sorted query when this is nil (migrated/restored data). Unidirectional to-one;
	/// nullified if the referenced position is deleted.
	@Relationship(deleteRule: .nullify)
	var latestPositionCache: PositionEntity?

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

	@Relationship(deleteRule: .nullify, inverse: \StatusMessageConfigEntity.statusMessageConfigNode)
	var statusMessageConfig: StatusMessageConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \StoreForwardConfigEntity.storeForwardConfigNode)
	var storeForwardConfig: StoreForwardConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \TAKConfigEntity.takConfigNode)
	var takConfig: TAKConfigEntity?

	@Relationship(deleteRule: .nullify, inverse: \TrafficManagementConfigEntity.trafficManagementConfigNode)
	var trafficManagementConfig: TrafficManagementConfigEntity?

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

extension NodeInfoEntity {
	/// Orders nodes for the admin / configuration node picker in `Settings.swift`:
	/// favorited nodes first, then non-favorites, with each group keeping the input's
	/// relative order. This restores the favorite-on-top behavior of the legacy
	/// CoreData `@FetchRequest` sort, which was lost in the SwiftData conversion
	/// (PR #1668).
	///
	/// `nodes` is expected to already be sorted by `lastHeard` descending — as the
	/// Settings `@Query` provides — so the partition yields favorites (most-recent
	/// first) ahead of non-favorites (most-recent first). It's a `Bool`-keyed
	/// partition rather than a SwiftData `@Query` sort because `favorite` is a
	/// `Bool`, and `Bool` is not `Comparable`, so it cannot be a `SortDescriptor`
	/// key on a non-`NSObject` `@Model`.
	///
	/// Implemented as a stable O(n) partition (rather than an O(n log n) re-sort) so
	/// it is cheap to call per render, and deterministic across re-renders as long as
	/// the input order is stable.
	static func adminPickerOrder(_ nodes: [NodeInfoEntity]) -> [NodeInfoEntity] {
		nodes.filter(\.favorite) + nodes.filter { !$0.favorite }
	}
}
