import Foundation
import CoreData
import MeshtasticProtobufs

extension DeviceMetadataEntity {
	convenience init(
		context: NSManagedObjectContext,
		metadata: DeviceMetadata
	) {
		self.init(context: context)
		self.time = Date()
		self.deviceStateVersion = Int32(metadata.deviceStateVersion)
		self.canShutdown = metadata.canShutdown
		self.hasWifi = metadata.hasWifi_p
		self.hasBluetooth = metadata.hasBluetooth_p
		self.hasEthernet	= metadata.hasEthernet_p
		self.role = Int32(metadata.role.rawValue)
		self.positionFlags = Int32(metadata.positionFlags)
		// Swift does strings weird, this does work to get the version without the github hash
		let lastDotIndex = metadata.firmwareVersion.lastIndex(of: ".")
		var version = metadata.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: metadata.firmwareVersion))]
		version = version.dropLast()
		self.firmwareVersion = String(version)
	}
}
