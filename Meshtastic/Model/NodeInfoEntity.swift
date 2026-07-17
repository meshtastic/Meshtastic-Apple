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
	/// True when this node signs its broadcast packets via XEdDSA and the radio has verified at least one
	/// (NodeInfo.has_xeddsa_signed, field 14). Observed automatic trust — not a configurable setting.
	var hasXeddsaSigned: Bool = false
	var hopsAway: Int32 = 0
	var id: Int64 = 0
	var ignored: Bool = false
	var lastHeard: Date?
	/// Live status message broadcast by the node over NODE_STATUS_APP (nil when empty).
	/// Distinct from `statusMessageConfig`, which is the configured value retrieved via admin.
	var nodeStatus: String?
	@Attribute(.unique) var num: Int64 = 0
	var peripheralId: String?
	/// User-editable per-channel power labels (e.g. "Solar", "Battery", "Load"), indexed 0-2.
	/// A missing/empty entry falls back to the generic "Channel N" in the UI. Per meshtastic/design#53.
	var powerChannelLabels: [String] = []
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

	@Relationship(deleteRule: .cascade, inverse: \MeshBeaconConfigEntity.meshBeaconConfigNode)
	var meshBeaconConfig: MeshBeaconConfigEntity?

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

	/// The status message to render on read-only surfaces (node list card and node
	/// details). Prefers the live broadcast value (`nodeStatus`, NODE_STATUS_APP) and
	/// falls back to the admin-configured value (`statusMessageConfig`) so the local
	/// node — which knows its config before it re-broadcasts — still shows its own status.
	///
	/// Each candidate is whitespace-trimmed *before* the emptiness test so a whitespace-only
	/// broadcast doesn't suppress an otherwise-configured value. Returns `nil` when both are
	/// empty/unset/whitespace-only so callers omit the row entirely (no icon, no label, no
	/// placeholder — per the design spec). The value is untrusted free text from the mesh:
	/// surface it verbatim and never as markup.
	///
	/// Safe to read directly in the hot list-row path: `StatusMessageConfigEntity` is only
	/// ever inserted/updated and (via `.nullify`) is never deleted independently of its node,
	/// so it can't fault underneath the row the way pruned `PositionEntity` rows can — i.e. it
	/// does not belong in the `NodeListRowSummary` value-snapshot, and keeping it inline lets
	/// the row re-render reactively when `nodeStatus` changes.
	var statusMessageDisplay: String? {
		NodeInfoEntity.displayableStatus(nodeStatus) ?? NodeInfoEntity.displayableStatus(statusMessageConfig?.nodeStatus)
	}

	/// Trims a candidate status and returns `nil` unless it contains at least one *visible*
	/// character. Plain `whitespacesAndNewlines` trimming isn't enough: an untrusted broadcast
	/// can be composed entirely of zero-width / format / control characters (U+200B, U+FEFF,
	/// U+2060, the bidi marks, …) that pass an `isEmpty` test yet render as a blank row with
	/// just the Notes icon. Treat such all-invisible strings as empty.
	private static func displayableStatus(_ raw: String?) -> String? {
		guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
			return nil
		}
		let hasVisible = trimmed.unicodeScalars.contains { scalar in
			switch scalar.properties.generalCategory {
			case .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator,
				 .nonspacingMark, .enclosingMark:
				return false
			default:
				return true
			}
		}
		return hasVisible ? trimmed : nil
	}

	/// The value the status-message editor should prefill. Prefer the configured status, but when
	/// it has no *displayable* content (blank, whitespace-only, or invisible-only — the same cases
	/// `displayableStatus` rejects) fall back to the node's live broadcast if that one is
	/// displayable. Without this the cards/detail can show the live broadcast while the editor
	/// prefills an apparently-blank configured value — a user-visible mismatch. A non-displayable
	/// configured value with no displayable live fallback normalizes to "" rather than echoing the
	/// whitespace/invisible characters back into the field (which would show a non-zero byte count
	/// for an apparently-empty editor). Pure + static so it can be unit-tested directly.
	static func statusMessagePrefill(configured: String?, live: String?) -> String {
		if let configured, displayableStatus(configured) != nil {
			return configured
		}
		if let live, displayableStatus(live) != nil {
			return live
		}
		return ""
	}
}
