//
//  FirmwareReleaseEntity.swift
//  Meshtastic
//
//  SwiftData model for firmware releases.
//

import Foundation
import SwiftData

@Model
final class FirmwareReleaseEntity {
	var pageUrl: String?
	var releaseNotes: String?
	var releaseType: String?
	var title: String?
	var versionId: String = ""
	var versionMajor: Int32 = 0
	var versionMinor: Int32 = 0
	var versionPatch: Int32 = 0

	init() {}
}
