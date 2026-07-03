// MARK: DiscoveryPresetResultEntity
//
//  DiscoveryPresetResultEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import SwiftData

@Model
final class DiscoveryPresetResultEntity {
	var presetName: String = ""
	var dwellDurationSeconds: Int = 0
	var uniqueNodesFound: Int = 0
	var directNeighborCount: Int = 0
	var meshNeighborCount: Int = 0
	var infrastructureNodeCount: Int = 0
	var messageCount: Int = 0
	var sensorPacketCount: Int = 0
	var averageChannelUtilization: Double = 0.0
	var averageAirtimeRate: Double = 0.0
	var packetSuccessRate: Double = 0.0
	var packetFailureRate: Double = 0.0
	var aiSummaryText: String = ""

	// Raw local stats (mirrors live activity data)
	var numPacketsTx: Int = 0
	var numPacketsRx: Int = 0
	var numPacketsRxBad: Int = 0
	var numRxDupe: Int = 0
	var numTxRelay: Int = 0
	var numTxRelayCanceled: Int = 0
	var numOnlineNodes: Int = 0
	var numTotalNodes: Int = 0
	var uptimeSeconds: Int = 0

	/// Average RF noise floor (dBm) from the connected node's local-stats telemetry collected
	/// during this preset's dwell. Noise floor is frequency-specific, so this characterizes how
	/// quiet the channel was on the preset's frequency — lower (more negative) is quieter/better.
	/// 0.0 means no noise-floor data was available (noise floor readings are always negative).
	var averageNoiseFloor: Double = 0.0
	/// Number of local-stats samples that contributed to `averageNoiseFloor`.
	var noiseFloorSampleCount: Int = 0

	var session: DiscoverySessionEntity?

	@Relationship(deleteRule: .nullify, inverse: \DiscoveredNodeEntity.presetResult)
	var nodes: [DiscoveredNodeEntity] = []

	init() {}
}
