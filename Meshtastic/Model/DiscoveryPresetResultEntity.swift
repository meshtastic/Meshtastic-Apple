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

	var session: DiscoverySessionEntity?

	@Relationship(deleteRule: .nullify, inverse: \DiscoveredNodeEntity.presetResult)
	var nodes: [DiscoveredNodeEntity] = []

	init() {}
}
