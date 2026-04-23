//
//  DeviceHardwareTagEntity.swift
//  Meshtastic
//
//  SwiftData model for device hardware tags.
//

import Foundation
import SwiftData

@Model
final class DeviceHardwareTagEntity {
	var tag: String = ""
	var devices: [DeviceHardwareEntity] = []

	init() {}
}
