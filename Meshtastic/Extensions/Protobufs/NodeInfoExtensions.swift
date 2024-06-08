import Foundation
import MeshtasticProtobufs

extension NodeInfo {
	var isValidPosition: Bool {
		hasPosition &&
			position.longitudeI != 0 &&
			position.latitudeI != 0 &&
			position.latitudeI != 373346000 &&
			position.longitudeI != -1220090000
	}
}
