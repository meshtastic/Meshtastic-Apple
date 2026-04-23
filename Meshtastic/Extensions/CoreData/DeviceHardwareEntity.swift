//
//  DeviceHardwareEntity.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/25.
//

import Foundation
import SwiftData

@Model
final class DeviceHardwareEntity {
	var activelySupported: Bool = false
	var architecture: String?
	var displayName: String?
	var hwModel: Int64 = 0
	var hwModelSlug: String?
	var platformioTarget: String?

	@Relationship(deleteRule: .nullify, inverse: \DeviceHardwareImageEntity.device)
	var images: [DeviceHardwareImageEntity] = []

	@Relationship(deleteRule: .nullify, inverse: \DeviceHardwareTagEntity.devices)
	var tags: [DeviceHardwareTagEntity] = []

	init() {}
}
