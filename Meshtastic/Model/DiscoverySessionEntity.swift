// MARK: DiscoverySessionEntity
//
//  DiscoverySessionEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import SwiftData

@Model
final class DiscoverySessionEntity {
	var timestamp: Date = Date()
	var presetsScanned: String = ""
	var totalUniqueNodes: Int = 0
	var averageChannelUtilization: Double = 0.0
	var totalTextMessages: Int = 0
	var totalSensorPackets: Int = 0
	var furthestNodeDistance: Double = 0.0
	var completionStatus: String = "inProgress"
	var aiSummaryText: String = ""
	var homePreset: String = ""
	var userLatitude: Double = 0.0
	var userLongitude: Double = 0.0

	@Relationship(deleteRule: .cascade, inverse: \DiscoveryPresetResultEntity.session)
	var presetResults: [DiscoveryPresetResultEntity] = []

	@Relationship(deleteRule: .cascade, inverse: \DiscoveredNodeEntity.session)
	var discoveredNodes: [DiscoveredNodeEntity] = []

	init() {}
}
