import Foundation
import MeshtasticProtobufs

// Default of 0 is auto
enum DisplayModes: Int, CaseIterable, Identifiable {
	case defaultMode = 0
	case twoColor = 1
	case inverted = 2
	case color = 3

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .defaultMode:
			return "Default 128x64 screen layout"

		case .twoColor:
			return "Optimized for 2-color display"

		case .inverted:
			return "Inverted top bar; 2-color display"

		case .color:
			return "Full color display"
		}
	}

	func protoEnumValue() -> Config.DisplayConfig.DisplayMode {
		switch self {
		case .defaultMode:
			return Config.DisplayConfig.DisplayMode.default

		case .twoColor:
			return Config.DisplayConfig.DisplayMode.twocolor

		case .inverted:
			return Config.DisplayConfig.DisplayMode.inverted

		case .color:
			return Config.DisplayConfig.DisplayMode.color
		}
	}
}
