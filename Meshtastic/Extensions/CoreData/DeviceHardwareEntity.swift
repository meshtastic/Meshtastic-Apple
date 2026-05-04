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
	var hasInkHud: Bool = false
	var hasMui: Bool = false
	var hwModel: Int64 = 0
	var hwModelSlug: String?
	var key: String?
	var partitionScheme: String?
	var platformioTarget: String?
	var requiresDfu: Bool = false
	var supportLevel: Int = 0
	var variant: String?

	@Relationship(deleteRule: .nullify, inverse: \DeviceHardwareImageEntity.device)
	var images: [DeviceHardwareImageEntity] = []

	@Relationship(deleteRule: .nullify, inverse: \DeviceHardwareTagEntity.devices)
	var tags: [DeviceHardwareTagEntity] = []

	init() {}
}
