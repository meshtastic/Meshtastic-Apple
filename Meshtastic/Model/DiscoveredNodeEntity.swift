// MARK: DiscoveredNodeEntity
//
//  DiscoveredNodeEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import SwiftData

@Model
final class DiscoveredNodeEntity {
	var nodeNum: Int64 = 0
	var shortName: String = ""
	var longName: String = ""
	var neighborType: String = "direct"
	var latitude: Double = 0.0
	var longitude: Double = 0.0
	var distanceFromUser: Double = 0.0
	var hopCount: Int = 0
	var snr: Float = 0.0
	var rssi: Int = 0
	var messageCount: Int = 0
	var sensorPacketCount: Int = 0
	var isInfrastructure: Bool = false
	var presetName: String = ""

	var session: DiscoverySessionEntity?
	var presetResult: DiscoveryPresetResultEntity?

	/// FR-011: messageCount >= sensorPacketCount → person.2.fill, else thermometer.medium
	var iconName: String {
		messageCount >= sensorPacketCount ? "person.2.fill" : "thermometer.medium"
	}

	init() {}
}
