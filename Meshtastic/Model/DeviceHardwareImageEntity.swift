//
//  DeviceHardwareImageEntity.swift
//  Meshtastic
//
//  SwiftData model for device hardware images.
//

import Foundation
import SwiftData

@Model
final class DeviceHardwareImageEntity {
	var eTag: String?
	var fileName: String?
	var svgData: Data?
	var device: DeviceHardwareEntity?

	init() {}
}
