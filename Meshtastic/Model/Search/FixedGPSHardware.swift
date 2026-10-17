//
//  FixedGPSHardware.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//
import MeshtasticProtobufs

/// Boards whose maker wired the GPS, read from the `oem_fixed_gps` flag on their
/// `HardwareModel` value. The `diy_only` GPS pin settings do not apply to these
/// boards and are hidden; any other or unknown board keeps them.
enum FixedGPSHardware {

	/// True when `hwModelId` names a `HardwareModel` flagged `oem_fixed_gps`.
	static func hasFixedGPS(hwModelId: Int32?) -> Bool {
		guard let hwModelId, let model = HardwareModel(rawValue: Int(hwModelId)) else { return false }
		return model.metadata?.oemFixedGps == true
	}
}
