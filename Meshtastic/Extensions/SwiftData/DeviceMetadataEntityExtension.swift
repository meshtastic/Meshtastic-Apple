import Foundation
import SwiftData
import MeshtasticProtobufs

extension DeviceMetadataEntity {
	convenience init(metadata: DeviceMetadata) {
		self.init()
		self.time = Date()
		self.deviceStateVersion = Int32(metadata.deviceStateVersion)
		self.canShutdown = metadata.canShutdown
		self.hasWifi = metadata.hasWifi_p
		self.hasBluetooth = metadata.hasBluetooth_p
		self.hasBuzzer = metadata.hasBuzzer_p
		self.hasEthernet	= metadata.hasEthernet_p
		self.role = Int32(metadata.role.rawValue)
		self.positionFlags = Int32(metadata.positionFlags)
		self.firmwareVersion = Self.displayFirmwareVersion(from: metadata.firmwareVersion)
	}
}
