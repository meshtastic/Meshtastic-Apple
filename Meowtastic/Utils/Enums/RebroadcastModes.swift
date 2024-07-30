import Foundation
import MeshtasticProtobufs

enum RebroadcastModes: Int, CaseIterable, Identifiable {
	case all = 0
	case allSkipDecoding = 1
	case localOnly = 2
	case knownOnly = 3

	var id: Int {
		self.rawValue
	}

	var name: String {
		switch self {
		case .all:
			return "All"

		case .allSkipDecoding:
			return "All Skip Decoding"

		case .localOnly:
			return "Local Only"

		case .knownOnly:
			return "Known Only"
		}
	}

	var description: String {
		switch self {
		case .all:
			return
"""
Rebroadcast any observed message, if it was on our private channel or from another mesh with the same lora params.
"""

		case .allSkipDecoding:
			return
"""
Same as behavior as ALL but skips packet decoding and simply rebroadcasts them. Only available in Repeater role. Setting this on any other roles will result in ALL behavior.
"""

		case .localOnly:
			return
"""
Ignores observed messages from foreign meshes that are open or those which it cannot decrypt. Only rebroadcasts message on the nodes local primary / secondary channels.
"""

		case .knownOnly:
			return
"""
Ignores observed messages from foreign meshes like Local Only, but takes it step further by also ignoring messages from nodes not already in the node's known list.
"""
		}
	}

	func protoEnumValue() -> Config.DeviceConfig.RebroadcastMode {
		switch self {
		case .all:
			return Config.DeviceConfig.RebroadcastMode.all

		case .allSkipDecoding:
			return Config.DeviceConfig.RebroadcastMode.allSkipDecoding

		case .localOnly:
			return Config.DeviceConfig.RebroadcastMode.localOnly

		case .knownOnly:
			return Config.DeviceConfig.RebroadcastMode.knownOnly
		}
	}
}
